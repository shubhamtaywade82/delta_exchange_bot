# frozen_string_literal: true

require "delta_exchange"
require_relative "config"
require_relative "product_cache"
require_relative "supervisor"
require_relative "feed/price_store"
require_relative "feed/websocket_feed"
require_relative "strategy/multi_timeframe"
require_relative "account/capital_manager"
require_relative "execution/risk_calculator"
require_relative "execution/position_tracker"
require_relative "execution/order_manager"
require_relative "notifications/logger"
require_relative "notifications/telegram_notifier"

module Bot
  class Runner
    STRATEGY_INTERVAL_SECONDS      = 300   # 5 minutes
    TRAILING_STOP_INTERVAL_SECONDS = 15

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
      @capital_manager  = Account::CapitalManager.new(usd_to_inr_rate: @config.usd_to_inr_rate)
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

      trap("INT")  { graceful_shutdown(supervisor) }
      trap("TERM") { graceful_shutdown(supervisor) }

      supervisor.start_all
      supervisor.monitor
    end

    private

    def setup_delta_exchange
      DeltaExchange.configure do |c|
        c.api_key    = ENV.fetch("DELTA_API_KEY")
        c.api_secret = ENV.fetch("DELTA_API_SECRET")
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
        end

        sleep TRAILING_STOP_INTERVAL_SECONDS
      end
    end

    def reconcile_open_positions
      adopted = 0

      @config.symbol_names.each do |symbol|
        product_id = @product_cache.product_id_for(symbol)
        pos = DeltaExchange::Models::Position.find(product_id)
        next unless pos && pos.size.to_i > 0

        side     = pos.side == "buy" ? :long : :short
        leverage = @config.leverage_for(symbol)

        @position_tracker.open(
          symbol:      symbol,
          side:        side,
          lots:        pos.size.to_i,
          entry_price: pos.entry_price.to_f,
          leverage:    leverage,
          trail_pct:   @config.trailing_stop_pct
        )
        adopted += 1
      rescue StandardError => e
        @logger.warn("reconcile_failed", symbol: symbol, message: e.message)
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
