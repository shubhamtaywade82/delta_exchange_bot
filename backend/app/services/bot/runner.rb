# frozen_string_literal: true


module Bot
  class Runner
    STRATEGY_INTERVAL_SECONDS      = 15    # Reduced for testing/faster signals
    TRAILING_STOP_INTERVAL_SECONDS = 5     # Faster tracking
    PORTFOLIO_LOG_INTERVAL_SECONDS = 30    # Portfolio snapshot frequency

    def initialize(config:)
      @config = config
      setup_delta_exchange
      @logger   = Notifications::Logger.new(file: config.log_file, level: config.log_level)
      @notifier = Notifications::TelegramNotifier.new(
        enabled: config.telegram_enabled?,
        token:   config.telegram_token,
        chat_id: config.telegram_chat_id
      )
    end

    def start
      @logger.info("bot_starting", mode: @config.mode, symbols: @config.symbol_names)

      products       = DeltaExchange::Models::Product.all
      @product_cache = ProductCache.new(symbols: @config.symbol_names, products: products)

      @price_store      = Feed::PriceStore.new
      @position_tracker = Execution::PositionTracker.new
      @capital_manager  = Account::CapitalManager.new(usd_to_inr_rate: @config.usd_to_inr_rate,
                                                       dry_run: @config.dry_run?)
      @risk_calculator  = Execution::RiskCalculator.new(usd_to_inr_rate: @config.usd_to_inr_rate)

      client       = DeltaExchange::Client.new
      @market_data = client.market_data

      @mtf = Strategy::MultiTimeframe.new(config: @config, market_data: @market_data, logger: @logger)

      @order_manager = Execution::OrderManager.new(
        config:           @config,
        product_cache:    @product_cache,
        position_tracker: @position_tracker,
        risk_calculator:  @risk_calculator,
        capital_manager:  @capital_manager,
        logger:           @logger,
        notifier:         @notifier
      )

      @ws_feed = Feed::WebsocketFeed.new(
        symbols:     @config.symbol_names,
        price_store: @price_store,
        logger:      @logger,
        testnet:     @config.testnet?
      )

      reconcile_open_positions

      supervisor = Supervisor.new(logger: @logger, notifier: @notifier)

      supervisor.register(:websocket)     { @ws_feed.start }
      supervisor.register(:strategy)      { run_strategy_loop }
      supervisor.register(:trailing_stop) { run_trailing_stop_loop }
      supervisor.register(:portfolio_log) { run_portfolio_log_loop }

      @shutdown_requested = false
      trap("INT")  { @shutdown_requested = true }
      trap("TERM") { @shutdown_requested = true }

      supervisor.start_all
      
      until @shutdown_requested
        supervisor.monitor
        sleep 1
      end

      graceful_shutdown(supervisor)
    end

    private

    def setup_delta_exchange
      DeltaExchange.configure do |c|
        c.api_key    = ENV["DELTA_API_KEY"]    or raise "Missing env var: DELTA_API_KEY"
        c.api_secret = ENV["DELTA_API_SECRET"] or raise "Missing env var: DELTA_API_SECRET"
        c.testnet    = @config.testnet?
      end
    end

    def run_strategy_loop
      loop do
        @config.symbol_names.each do |symbol|
          next if @position_tracker.open?(symbol)
          next if @position_tracker.count >= @config.max_concurrent_positions

          ltp = @price_store.get(symbol)
          unless ltp
            @logger.warn("skip_no_ltp", symbol: symbol)
            next
          end

          signal = @mtf.evaluate(symbol, current_price: ltp)
          @order_manager.execute_signal(signal) if signal
        rescue DeltaExchange::RateLimitError => e
          @logger.warn("rate_limited", symbol: symbol, retry_after: e.retry_after_seconds)
          sleep(e.retry_after_seconds)
        rescue StandardError => e
          @logger.error("strategy_error", symbol: symbol, message: e.message)
        end

        sleep STRATEGY_INTERVAL_SECONDS
      end
    end

    def run_trailing_stop_loop
      loop do
        @position_tracker.all.each do |symbol, _pos|
          ltp = @price_store.get(symbol)
          next unless ltp

          result = @position_tracker.update_trailing_stop(symbol, ltp)
          next unless result == :exit

          @order_manager.close_position(symbol, exit_price: ltp, reason: :trail_stop)
        rescue StandardError => e
          @logger.error("trailing_stop_error", symbol: symbol, message: e.message)
        end

        sleep TRAILING_STOP_INTERVAL_SECONDS
      end
    end

    def run_portfolio_log_loop
      loop do
        sleep PORTFOLIO_LOG_INTERVAL_SECONDS

        snapshot       = @position_tracker.snapshot(@price_store.all)
        total_capital  = @capital_manager.available_usdt
        blocked_margin = snapshot[:blocked_margin]
        available      = (total_capital - blocked_margin).round(2)
        unrealized     = snapshot[:unrealized_pnl]
        realized       = @order_manager.realized_pnl.round(2)

        @logger.info("portfolio_snapshot",
          open_positions:       snapshot[:open_count],
          total_capital_usd:    total_capital.round(2),
          blocked_margin_usd:   blocked_margin,
          available_margin_usd: available,
          realized_pnl_usd:     realized,
          unrealized_pnl_usd:   unrealized,
          total_pnl_usd:        (realized + unrealized).round(2),
          positions:            snapshot[:positions].values
        )
      rescue StandardError => e
        @logger.error("portfolio_log_error", message: e.message)
      end
    end

    def reconcile_open_positions
      return if @config.dry_run?
      adopted = 0

      @config.symbol_names.each do |symbol|
        begin
          product_id = @product_cache.product_id_for(symbol)
          # Fetch positions for this specific product to avoid "bad_schema" errors
          # that occur when calling Position.all without filters.
          positions = DeltaExchange::Models::Position.all(product_id: product_id) || []
          pos = positions.find { |p| p.product_id == product_id }
          next unless pos && pos.size.to_i.positive?

          side           = pos.side == "buy" ? :long : :short
          leverage       = @config.leverage_for(symbol)
          contract_value = @product_cache.contract_value_for(symbol)

          @position_tracker.open(
            symbol:         symbol,
            side:           side,
            lots:           pos.size.to_i,
            entry_price:    pos.entry_price.to_f,
            leverage:       leverage,
            contract_value: contract_value,
            trail_pct:      @config.trailing_stop_pct
          )
          adopted += 1
        rescue StandardError => e
          @logger.warn("reconcile_failed", symbol: symbol, message: e.message)
        end
      end

      return unless adopted.positive?

      @logger.info("positions_reconciled", count: adopted)
      @notifier.send_message("♻️ Bot restarted — re-adopted #{adopted} open position(s) from API")
    end

    def graceful_shutdown(supervisor)
      @logger.info("bot_stopping")
      supervisor.stop_all
      @ws_feed&.stop
      exit 0
    end
  end
end
