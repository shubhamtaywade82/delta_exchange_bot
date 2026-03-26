# frozen_string_literal: true

module Trading
  module MarketData
    class CandleBuilder
      def initialize(symbol:, interval_seconds:)
        @symbol           = symbol
        @interval_seconds = interval_seconds
        @current          = nil
        @bucket           = nil
      end

      # Returns a closed Candle when an interval boundary is crossed, nil otherwise.
      def on_tick(price:, timestamp:, volume: 0.0)
        bucket = (timestamp / @interval_seconds) * @interval_seconds

        if @bucket != bucket
          completed = @current
          start_new_candle(price, bucket, volume)
          completed&.tap { |c| c.closed = true; c.closed_at = Time.at(@bucket) }
        else
          update_candle(price, volume)
          nil
        end
      end

      private

      def start_new_candle(price, bucket, volume)
        @bucket  = bucket
        @current = Candle.new(
          symbol:    @symbol,
          open:      price,
          high:      price,
          low:       price,
          close:     price,
          volume:    volume.to_f,
          opened_at: Time.at(bucket),
          closed_at: nil,
          closed:    false
        )
      end

      def update_candle(price, volume)
        @current.high   = [@current.high, price].max
        @current.low    = [@current.low, price].min
        @current.close  = price
        @current.volume += volume.to_f
      end
    end
  end
end
