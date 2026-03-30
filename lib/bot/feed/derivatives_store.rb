# frozen_string_literal: true

module Bot
  module Feed
    class DerivativesStore
      FUNDING_EXTREME_THRESHOLD = 0.0005  # 0.05%

      def initialize(products:, symbols:, poll_interval: 30, logger: nil)
        @products      = products
        @symbols       = symbols
        @poll_interval = poll_interval
        @logger        = logger
        @data          = {}
        @mutex         = Mutex.new
      end

      def update_funding_rate(symbol, rate:)
        @mutex.synchronize do
          @data[symbol] ||= {}
          @data[symbol][:funding_rate]    = rate.to_f
          @data[symbol][:funding_extreme] = rate.to_f.abs > FUNDING_EXTREME_THRESHOLD
        end
      end

      def update_oi(symbol, oi_usd:)
        @mutex.synchronize do
          @data[symbol] ||= {}
          prev = @data[symbol][:oi_usd]
          @data[symbol][:oi_usd]   = oi_usd.to_f
          @data[symbol][:oi_trend] = prev ? (oi_usd.to_f > prev ? :rising : :falling) : :rising
        end
      end

      def get(symbol)
        @mutex.synchronize do
          d = @data[symbol] || {}
          {
            oi_usd:          d[:oi_usd],
            oi_trend:        d[:oi_trend],
            funding_rate:    d[:funding_rate],
            funding_extreme: d[:funding_extreme] || false
          }
        end
      end

      def poll_oi
        @symbols.each do |symbol|
          ticker = @products.ticker(symbol)
          oi_usd = ticker["oi_value_usd"]&.to_f
          next unless oi_usd&.positive?

          update_oi(symbol, oi_usd: oi_usd)

          fr = ticker["funding_rate"]&.to_f
          update_funding_rate(symbol, rate: fr) if fr && get(symbol)[:funding_rate].nil?
        rescue StandardError => e
          @logger&.error("oi_poll_error", symbol: symbol, message: e.message)
        end
      end

      def start_polling
        Thread.new do
          loop do
            poll_oi
            sleep @poll_interval
          rescue StandardError => e
            @logger&.error("oi_poll_thread_error", message: e.message)
            sleep @poll_interval
          end
        end
      end
    end
  end
end
