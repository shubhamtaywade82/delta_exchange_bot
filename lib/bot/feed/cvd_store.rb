# frozen_string_literal: true

module Bot
  module Feed
    class CvdStore
      def initialize(window: 50)
        @window = window
        @mutex  = Mutex.new
        @data   = Hash.new { |h, k| h[k] = { cum_delta: 0.0, window_deltas: [] } }
      end

      def record_trade(symbol, side:, size:)
        delta = side == "buy" ? size.to_f : -size.to_f
        @mutex.synchronize do
          d = @data[symbol]
          d[:cum_delta] += delta
          d[:window_deltas] << delta
          d[:window_deltas] = d[:window_deltas].last(@window)
        end
      end

      def get(symbol)
        @mutex.synchronize do
          d = @data[symbol]
          window_sum = d[:window_deltas].sum
          trend = if window_sum > 0
                    :bullish
                  elsif window_sum < 0
                    :bearish
                  else
                    :neutral
                  end
          { cumulative_delta: d[:cum_delta].round(2), delta_trend: trend }
        end
      end
    end
  end
end
