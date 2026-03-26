# frozen_string_literal: true

module Trading
  class Runner
    STRATEGY_INTERVAL = 60 # 1 minute

    def initialize(session_id:, client: nil)
      @session = TradingSession.find(session_id)
      @client  = client || build_client
      @running = true
      @last_strategy_run = 0
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
        if now - @last_strategy_run >= STRATEGY_INTERVAL
          run_strategy
          @last_strategy_run = now
        end

        LiquidationGuard.check_all(client: @client)
        FundingMonitor.check_all(client: @client)
        sleep 5
      end
    end

    def run_strategy
      symbols = SymbolConfig.where(enabled: true).pluck(:symbol)
      config  = Bot::Config.load
      
      # Reuse the migrated strategy logic which fetches OHLCV from API
      strategy = Bot::Strategy::MultiTimeframe.new(
        client:      @client,
        config:      config,
        symbols:     symbols,
        logger:      Rails.logger,
        market_data: @client.market_data
      )

      symbols.each do |symbol|
        # 1. Evaluate strategy (fetches 1H, 15M, 5M OHLCV via REST API)
        ltp    = Rails.cache.read("ltp:#{symbol}") || fetch_last_price(symbol)
        signal = strategy.evaluate(symbol, current_price: ltp)
        next unless signal

        # 2. Process signal
        converted = Events::SignalGenerated.new(
          symbol:           signal.symbol,
          side:             signal.side,
          entry_price:      signal.entry_price,
          candle_timestamp: signal.candle_ts,
          strategy:         @session.strategy,
          session_id:       @session.id
        )

        EventBus.publish(:signal_generated, converted)
        ExecutionEngine.execute(converted, session: @session, client: @client)
      rescue => e
        Rails.logger.error("[Runner] Strategy error for #{symbol}: #{e.message}")
      end
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
      DeltaExchange::Client.new(
        api_key:    ENV.fetch("DELTA_API_KEY"),
        api_secret: ENV.fetch("DELTA_API_SECRET")
      )
    end
  end
end
