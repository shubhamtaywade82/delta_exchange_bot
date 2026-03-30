# frozen_string_literal: true

require "redis"

module Bot
  module Strategy
    class ScanningService
      def initialize(config:, market_data:, logger:)
        @config      = config
        @market_data = market_data
        @logger      = logger
        @strategy    = MultiTimeframe.new(config: config, market_data: market_data, logger: logger)
        @redis       = Redis.new
      end

      # Iterates symbols with a staggered delay to avoid rate limits.
      # Returns an array of Signals found.
      def scan(symbols, current_prices:)
        @logger.info("scan_started_v2", count: symbols.size, symbols: symbols, price_keys: current_prices.keys)
        signals = []

        symbols.each_with_index do |symbol, index|
          @logger.info("scanning_symbol_step", symbol: symbol, index: index)
          # Staggered delay (except for the first symbol)
          sleep 1.0 if index.positive?

          ltp = current_prices[symbol]
          if ltp.nil?
            @logger.info("scan_skip_no_ltp", symbol: symbol)
            next
          end

          @logger.info("scan_evaluating", symbol: symbol, ltp: ltp)
          begin
            signal = @strategy.evaluate(symbol, current_price: ltp)
            signals << signal if signal
          rescue DeltaExchange::RateLimitError => e
            @logger.warn("scan_rate_limited", symbol: symbol, retry_after: e.retry_after_seconds)
            sleep(e.retry_after_seconds)
            # Retry once after sleep if it was a rate limit
            retry
          rescue StandardError => e
            @logger.error("scan_symbol_error", symbol: symbol, message: e.message)
          end
        end

        @logger.info("scan_completed", signals_found: signals.size)
        signals
      end
    end
  end
end
