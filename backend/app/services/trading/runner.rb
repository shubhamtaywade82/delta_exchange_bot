# frozen_string_literal: true

module Trading
  class Runner
    DEFAULT_STRATEGY_INTERVAL = 60

    def initialize(session_id:, client: nil)
      @session = TradingSession.find(session_id)
      @client  = client || build_client
      @running = true
      @last_strategy_run = 0
      @last_adaptive_observed_at = {}
    end

    def start
      Rails.logger.info("[Runner] Starting session #{@session.id} strategy=#{@session.strategy}")
      bootstrap!
      register_event_handlers!
      start_ws!
      run_loop
    ensure
      EventBus.reset!
      Rails.logger.info("[Runner] Session #{@session.id} exited cleanly")
    end

    def stop
      @running = false
    end

    private

    def bootstrap!
      if PaperTrading.enabled?
        Rails.logger.info("[Runner] Paper mode — skipping exchange position/order bootstrap")
        return
      end

      Bootstrap::SyncPositions.call(client: @client)
      Bootstrap::SyncOrders.call(client: @client, session: @session)
    end

    def register_event_handlers!
      EventBus.subscribe(:order_filled) do |event|
        Handlers::OrderHandler.new(event).call
      end
      EventBus.subscribe(:position_updated) do |event|
        Handlers::PositionHandler.new(event).call
      end
      EventBus.subscribe(:tick_received) do |tick|
        Handlers::TrailingStopHandler.new(tick, client: @client).call
      end
    end

    def start_ws!
      symbols  = SymbolConfig.where(enabled: true).pluck(:symbol)
      testnet  = @session.strategy.include?("testnet") || ENV["DELTA_TESTNET"] == "true"

      @ws_thread = Thread.new do
        # WsClient still useful for real-time LTP/PnL in UI via PriceStore
        MarketData::WsClient.new(client: @client, symbols: symbols, testnet: testnet).start
      rescue => e
        Rails.logger.error("[Runner] WS thread crashed: #{e.message}")
      end
    end

    def run_loop
      while running?
        now = Time.now.to_i
        if now - @last_strategy_run >= strategy_interval_seconds
          run_strategy
          @last_strategy_run = now
        end

        LiquidationGuard.check_all(client: @client)
        FundingMonitor.check_all(client: @client)
        sleep 5
      end
    end

    def strategy_interval_seconds
      Trading::RuntimeConfig.fetch_integer("runner.strategy_interval_seconds", default: DEFAULT_STRATEGY_INTERVAL)
    end

    # History/candles is unauthenticated and heavily rate-limited. Each symbol triggers 3 sequential
    # fetches (trend / confirm / entry). Without a gap, the 2nd+ symbols often get empty/error payloads,
    # insufficient_candles runs, and Redis never gets persist — only the first symbol stays fresh.
    def strategy_symbol_stagger_seconds
      Trading::RuntimeConfig.fetch_float(
        "runner.strategy_symbol_stagger_seconds",
        default: 2.5,
        env_key: "RUNNER_STRATEGY_SYMBOL_STAGGER_S"
      )
    end

    def run_strategy
      symbols = SymbolConfig.where(enabled: true).pluck(:symbol)
      config  = Bot::Config.load
      
      # Reuse the migrated strategy logic which fetches OHLCV from API
      strategy = Bot::Strategy::MultiTimeframe.new(
        config:      config,
        market_data: @client.market_data,
        logger:      Rails.logger
      )

      symbols.each_with_index do |symbol, index|
        sleep(strategy_symbol_stagger_seconds) if index.positive?

        ltp    = Rails.cache.read("ltp:#{symbol}") || fetch_last_price(symbol)
        signal = strategy.evaluate(symbol, current_price: ltp)
        if signal
          execute_signal(
            symbol: symbol,
            side: signal.side,
            entry_price: signal.entry_price,
            candle_timestamp: signal.candle_ts,
            strategy_name: @session.strategy,
            source: "mtf",
            context: {}
          )
          next
        end

        adaptive_signal = build_adaptive_signal(symbol: symbol, ltp: ltp)
        next unless adaptive_signal

        execute_signal(**adaptive_signal)
      rescue => e
        Rails.logger.error("[Runner] Strategy error for #{symbol}: #{e.message}")
      end
    end

    def execute_signal(symbol:, side:, entry_price:, candle_timestamp:, strategy_name:, source:, context:)
      signal_record = persist_signal(
        symbol: symbol,
        side: side,
        entry_price: entry_price,
        candle_timestamp: candle_timestamp,
        strategy_name: strategy_name,
        source: source,
        context: context
      )

      converted = Events::SignalGenerated.new(
        symbol: symbol,
        side: side,
        entry_price: entry_price,
        candle_timestamp: candle_timestamp,
        strategy: strategy_name,
        session_id: @session.id
      )

      EventBus.publish(:signal_generated, converted)
      ExecutionEngine.execute(converted, session: @session, client: @client)
      signal_record&.update!(status: "executed")
    rescue Trading::RiskManager::RiskError => e
      signal_record&.update!(status: "rejected", error_message: e.message)
      Rails.logger.warn("[Runner] Signal rejected for #{symbol}: #{e.message}")
      nil
    rescue StandardError => e
      signal_record&.update!(status: "failed", error_message: e.message)
      raise
    end

    def build_adaptive_signal(symbol:, ltp:)
      return nil if Position.active.exists?(symbol: symbol)

      context = Rails.cache.read("adaptive:entry_context:#{symbol}")
      return nil unless context.is_a?(Hash)

      decision = (context[:decision] || context["decision"]).to_s
      side = case decision
             when "buy" then :buy
             when "sell" then :sell
             else nil
             end
      return nil unless side

      observed_at = (context[:observed_at] || context["observed_at"]).to_i
      return nil if observed_at.zero? || observed_at == @last_adaptive_observed_at[symbol]

      @last_adaptive_observed_at[symbol] = observed_at
      strategy_name = context[:strategy] || context["strategy"] || "adaptive"

      {
        symbol: symbol,
        side: side,
        entry_price: ltp,
        candle_timestamp: observed_at,
        strategy_name: "adaptive:#{strategy_name}",
        source: "adaptive",
        context: context
      }
    end

    def persist_signal(symbol:, side:, entry_price:, candle_timestamp:, strategy_name:, source:, context:)
      GeneratedSignal.create!(
        trading_session_id: @session.id,
        symbol: symbol,
        side: side.to_s,
        entry_price: entry_price,
        candle_timestamp: candle_timestamp.to_i,
        strategy: strategy_name,
        source: source,
        status: "generated",
        context: context || {}
      )
    end

    def fetch_last_price(symbol)
      # Fallback if WS not populated cache yet
      ticker = @client.market_data.ticker(symbol)
      ticker["mark_price"]&.to_f || ticker["close"]&.to_f
    rescue
      0.0
    end

    def running?
      @running && @session.reload.running?
    rescue ActiveRecord::RecordNotFound
      false
    end

    def build_client
      if PaperTrading.enabled?
        key    = ENV["DELTA_API_KEY"].to_s
        secret = ENV["DELTA_API_SECRET"].to_s
        return DeltaExchange::Client.new(api_key: key.presence, api_secret: secret.presence)
      end

      DeltaExchange::Client.new(
        api_key:    ENV.fetch("DELTA_API_KEY"),
        api_secret: ENV.fetch("DELTA_API_SECRET")
      )
    end
  end
end
