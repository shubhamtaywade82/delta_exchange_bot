# frozen_string_literal: true


module Bot
  class Runner
    STRATEGY_INTERVAL_SECONDS = 300 # 5-minute periodic scan for futures
    TRAILING_STOP_INTERVAL_SECONDS = 5     # Faster tracking
    PORTFOLIO_LOG_INTERVAL_SECONDS = 10    # Faster status updates for UI

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
      puts "Starting runner..."
      @logger.info("bot_starting", mode: @config.mode, symbols: @config.symbol_names)

      puts "Fetching products..."
      products       = DeltaExchange::Models::Product.all
      puts "Products fetched: #{products&.size || 0}"
      @product_cache = ProductCache.new(symbols: @config.symbol_names, products: products)

      @price_store      = Feed::PriceStore.new
      @position_tracker = Execution::PositionTracker.new
      @capital_manager  = Account::CapitalManager.new(
        usd_to_inr_rate:        @config.usd_to_inr_rate,
        dry_run:                @config.dry_run?,
        simulated_capital_inr:  @config.simulated_capital_inr
      )
      @risk_calculator  = Execution::RiskCalculator.new(usd_to_inr_rate: @config.usd_to_inr_rate)

      client       = DeltaExchange::Client.new
      @market_data = client.market_data

      @mtf_scanner = Strategy::ScanningService.new(config: @config, market_data: @market_data, logger: @logger)

      @order_manager = Execution::OrderManager.new(
        config:           @config,
        product_cache:    @product_cache,
        position_tracker: @position_tracker,
        risk_calculator:  @risk_calculator,
        capital_manager:  @capital_manager,
        price_store:      @price_store,
        logger:           @logger,
        notifier:         @notifier
      )

      @ws_feed = Feed::WebsocketFeed.new(
        symbols:     @config.symbol_names,
        price_store: @price_store,
        logger:      @logger,
        testnet:     @config.testnet?
      )

      puts "Reconciling positions..."
      reconcile_open_positions

      puts "Setting up supervisor..."
      supervisor = Supervisor.new(logger: @logger, notifier: @notifier)

      puts "Registering threads..."
      supervisor.register(:websocket)     { @ws_feed.start }
      supervisor.register(:strategy)      { run_strategy_loop }
      supervisor.register(:trailing_stop) { run_trailing_stop_loop }
      supervisor.register(:portfolio_log) { run_portfolio_log_loop }

      @shutdown_requested = false
      puts "Setting up traps..."
      trap("INT")  { @shutdown_requested = true }
      trap("TERM") { @shutdown_requested = true }

      puts "Starting supervisor..."
      supervisor.start_all
      
      puts "Bot is running. Monitoring..."
      until @shutdown_requested
        supervisor.monitor
        sleep 1
      end

      graceful_shutdown(supervisor)
    end

    private

    def setup_delta_exchange
      key    = ENV["DELTA_API_KEY"]
      secret = ENV["DELTA_API_SECRET"]

      if key.blank? || secret.blank?
        puts "❌ ERROR: Missing Delta Exchange API credentials in .env"
        puts "   Please set DELTA_API_KEY and DELTA_API_SECRET"
        exit 1
      end

      # Basic length check to catch placeholder values
      if key.length < 20 || secret.length < 40
        puts "⚠️ WARNING: Delta API credentials look too short. Check if they are correct."
      end

      DeltaExchange.configure do |c|
        c.api_key    = key
        c.api_secret = secret
        c.testnet    = @config.testnet?
      end
    end

    def run_strategy_loop
      loop do
        @logger.info("strategy_loop_tick")
        current_prices = @price_store.all
        
        # Staggered scan of all symbols
        signals = @mtf_scanner.scan(@config.symbol_names, current_prices: current_prices)
        
        signals.each do |signal|
          next if @position_tracker.open?(signal.symbol)
          @order_manager.execute_signal(signal)
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
        equity_usd     = @capital_manager.total_equity_usdt(unrealized_pnl: snapshot[:unrealized_pnl])
        blocked_margin = snapshot[:blocked_margin]
        available_usd  = @capital_manager.spendable_usdt(
          blocked_margin: blocked_margin,
          unrealized_pnl: snapshot[:unrealized_pnl]
        )
        unrealized     = snapshot[:unrealized_pnl]
        realized       = @order_manager.realized_pnl.round(2)

        @capital_manager.persist_state(
          blocked_margin: snapshot[:blocked_margin],
          unrealized_pnl: snapshot[:unrealized_pnl]
        )

        @logger.info("portfolio_snapshot",
          open_positions:       snapshot[:open_count],
          total_equity_usd:     equity_usd.round(2),
          blocked_margin_usd:   blocked_margin,
          available_margin_usd: available_usd.round(2),
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
