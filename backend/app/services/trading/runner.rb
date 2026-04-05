# frozen_string_literal: true

module Trading
  class Runner
    DEFAULT_STRATEGY_INTERVAL = 30

    def initialize(session_id:, client: nil)
      @session = TradingSession.find(session_id)
      @client  = client || build_client
      @running = true
      @last_strategy_run = 0
      @last_adaptive_observed_at = {}
      @strategy_logger = nil
    end

    def start
      Rails.logger.info("[Runner] Starting session #{@session.id} strategy=#{@session.strategy}")
      notify_startup_status
      bootstrap!
      register_event_handlers!
      start_ws!
      run_loop
    ensure
      notify_shutdown_status
      EventBus.reset!
      Rails.logger.info("[Runner] Session #{@session.id} exited cleanly")
    end

    def stop
      @running = false
    end

    private

    def strategy_session_logger
      @strategy_logger ||= build_strategy_session_logger
    end

    def build_strategy_session_logger
      cfg  = Bot::Config.load
      path = Rails.root.join(cfg.log_file)
      Bot::Notifications::StrategySessionLogger.new(
        file: path.to_s,
        level: cfg.log_level,
        rails_logger: Rails.logger
      )
    rescue StandardError => e
      HotPathErrorPolicy.log_swallowed_error(
        component: "Runner",
        operation: "build_strategy_session_logger",
        error:     e,
        log_level: :warn,
        session_id: @session.id
      )
      Rails.logger
    end

    def bootstrap!
      ensure_symbols_configured!

      if PaperTrading.enabled?
        Rails.logger.info("[Runner] Paper mode — skipping exchange position/order bootstrap")
        return
      end

      Bootstrap::SyncPositions.call(client: @client)
      Bootstrap::SyncOrders.call(client: @client, session: @session)
    end

    def ensure_symbols_configured!
      config = Bot::Config.load
      config.symbols.each do |s|
        row = SymbolConfig.find_or_initialize_by(symbol: s[:symbol])
        row.leverage = s[:leverage] if row.new_record? || row.leverage.nil?
        row.enabled = true
        row.save!
      end

      # Immediate sync so dashboard has data before first WS tick
      Trading::Delta::ProductCatalogSync.sync_all!
    rescue StandardError => e
      HotPathErrorPolicy.log_swallowed_error(
        component: "Runner",
        operation: "ensure_symbols_configured!",
        error:     e,
        log_level: :warn,
        session_id: @session.id
      )
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
      symbols  = Bot::Config.load.symbol_names
      testnet  = @session.strategy.include?("testnet") || ENV["DELTA_TESTNET"] == "true"

      @ws_thread = Thread.new do
        # WsClient still useful for real-time LTP/PnL in UI via PriceStore
        MarketData::WsClient.new(client: @client, symbols: symbols, testnet: testnet).start
      rescue StandardError => e
        HotPathErrorPolicy.log_swallowed_error(
          component: "Runner",
          operation: "ws_thread",
          error:     e,
          log_level: :error,
          session_id: @session.id
        )
      end
    end

    def run_loop
      while running?
        now = Time.current.to_i
        if now - @last_strategy_run >= strategy_interval_seconds
          run_strategy
          @last_strategy_run = now
        end

        NearLiquidationExit.check_all(client: @client)
        FundingMonitor.check_all(client: @client)
        sleep 5
      end
    end

    # How often to start a new full pass over the watchlist (not aligned to chart candle closes).
    def strategy_interval_seconds
      Trading::RuntimeConfig.fetch_integer("runner.strategy_interval_seconds", default: DEFAULT_STRATEGY_INTERVAL)
    end

    # Within a single pass, pause between symbols (seconds) so public /history/candles is not burst.
    # This is rate-limit spacing only — the next symbol runs a few seconds later, not on the next 5m bar.
    def strategy_symbol_stagger_seconds
      Trading::RuntimeConfig.fetch_float(
        "runner.strategy_symbol_stagger_seconds",
        default: 1.0,
        env_key: "RUNNER_STRATEGY_SYMBOL_STAGGER_S"
      )
    end

    def run_strategy
      pass_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      config  = Bot::Config.load
      symbols = config.symbol_names

      # MTF entries only — independent of Trading::Analysis::DigestBuilder / Ollama (analysis dashboard job).
      # Reuse the migrated strategy logic which fetches OHLCV from API
      strategy = Bot::Strategy::MultiTimeframe.new(
        config:      config,
        market_data: @client.market_data,
        logger:      strategy_session_logger
      )

      symbols.each_with_index do |symbol, index|
        sleep(strategy_symbol_stagger_seconds) if index.positive?

        ltp = normalized_ltp(symbol)
        unless ltp
          Rails.logger.warn("[Runner] Skipping #{symbol}: no positive LTP (cache or REST)")
          next
        end

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
      rescue StandardError => e
        HotPathErrorPolicy.log_swallowed_error(
          component: "Runner",
          operation: "run_strategy",
          error:     e,
          log_level: :error,
          session_id: @session.id,
          symbol:    symbol
        )
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - pass_started
      Rails.logger.info(
        "[Runner] Strategy pass complete symbols=#{symbols.size} elapsed_s=#{elapsed.round(2)} " \
        "(stagger=#{strategy_symbol_stagger_seconds}s between symbols; interval=#{strategy_interval_seconds}s between passes)"
      )
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
      order = ExecutionEngine.execute(converted, session: @session, client: @client)
      if order
        notify_signal_and_entry(order, converted)
        signal_record&.update!(status: "executed")
      else
        signal_record&.update!(
          status: "skipped_duplicate",
          error_message: "idempotency: same symbol/side/candle_timestamp already executed"
        )
      end
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

    def normalized_ltp(symbol)
      raw = Rails.cache.read("ltp:#{symbol}")
      candidate = raw.nil? ? nil : raw.to_f
      candidate = fetch_last_price(symbol) unless candidate&.positive?
      candidate&.positive? ? candidate : nil
    end

    def fetch_last_price(symbol)
      ticker = @client.market_data.ticker(symbol)
      extract_positive_ticker_price(ticker)
    rescue StandardError => e
      HotPathErrorPolicy.log_swallowed_error(
        component: "Runner",
        operation: "fetch_last_price",
        error:     e,
        log_level: :warn,
        session_id: @session.id,
        symbol:    symbol
      )
      nil
    end

    def extract_positive_ticker_price(ticker)
      %w[mark_price close].each do |key|
        next if ticker[key].nil?

        price = ticker[key].to_f
        return price if price.positive?
      end
      nil
    end

    def running?
      @running && @session.reload.running?
    rescue ActiveRecord::RecordNotFound
      false
    end

    def notify_startup_status
      symbols = Bot::Config.load.symbol_names.join(", ")
      paper = PaperTrading.enabled? ? "paper" : "live"
      TelegramNotifications.deliver do |n|
        n.notify_status(
          "Trading::Runner session #{@session.id} (#{@session.strategy}) — #{paper}. Symbols: #{symbols.presence || '(none)'}",
          status: "starting"
        )
      end
    end

    def notify_shutdown_status
      TelegramNotifications.deliver do |n|
        n.notify_status("Trading::Runner session #{@session.id} stopped.", status: "stopping")
      end
    end

    def notify_signal_and_entry(order, signal_event)
      TelegramNotifications.deliver do |n|
        n.notify_signal_generated(
          symbol: signal_event.symbol,
          side: signal_event.side,
          price: signal_event.entry_price.to_f,
          strategy: signal_event.strategy.to_s
        )
        notify_position_opened_if_applicable(n, order)
      end
    end

    def notify_position_opened_if_applicable(notifier, order)
      order.reload
      pos = order.position
      return unless pos && order.status == "filled"
      return unless Position::NET_OPEN_STATUSES.include?(pos.status)

      side_sym = pos.side.to_s.downcase.in?(%w[long buy]) ? :long : :short
      mode = PaperTrading.enabled? ? "paper" : "live"
      notifier.notify_trade_opened(
        symbol: pos.symbol,
        side: side_sym,
        price: pos.entry_price.to_f,
        lots: pos.size.to_f,
        added_lots: order.size.to_f,
        leverage: pos.leverage.to_i,
        trailing_stop: pos.stop_price.to_f,
        mode: mode
      )
    end

    def build_client
      RunnerClient.build
    end
  end
end
