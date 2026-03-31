# frozen_string_literal: true

module Trading
  module MarketData
    class CandleBuilder
      def initialize(symbol:, interval_seconds:)
        @symbol = symbol
        @interval_seconds = interval_seconds
        @current_candle = nil
      end

      def on_tick(price:, timestamp:, volume: 0.0)
        tick_time = Time.at(timestamp.to_i).utc

        if @current_candle.nil?
          @current_candle = start_candle(price: price, opened_at: interval_open_time(tick_time), volume: volume)
          return nil
        end

        if same_interval?(tick_time)
          update_candle!(price: price, volume: volume)
          return nil
        end

        closed = close_current_candle
        @current_candle = start_candle(price: price, opened_at: interval_open_time(tick_time), volume: volume)
        closed
      end

      private

      def interval_open_time(time)
        bucket = (time.to_i / @interval_seconds) * @interval_seconds
        Time.at(bucket).utc
      end

      def same_interval?(time)
        interval_open_time(time) == @current_candle.opened_at
      end

      def start_candle(price:, opened_at:, volume:)
        px = price.to_f
        Candle.new(
          symbol: @symbol,
          open: px,
          high: px,
          low: px,
          close: px,
          volume: volume.to_f,
          opened_at: opened_at,
          closed_at: nil,
          closed: false
        )
      end

      def update_candle!(price:, volume:)
        px = price.to_f
        @current_candle.high = [@current_candle.high.to_f, px].max
        @current_candle.low = [@current_candle.low.to_f, px].min
        @current_candle.close = px
        @current_candle.volume = @current_candle.volume.to_f + volume.to_f
      end

      def close_current_candle
        @current_candle.closed = true
        @current_candle.closed_at = @current_candle.opened_at + @interval_seconds
        @current_candle
      end
    end
  end
end
