# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      # Change of character: counter-structure break using recent swing pivots (shorter memory than BOS).
      module Choch
        def self.last_event(candles, swing: 3)
          return nil if candles.size < (swing * 2) + 5

          lows = SwingFractal.pivot_low_indices(candles, left: swing, right: swing)
          highs = SwingFractal.pivot_high_indices(candles, left: swing, right: swing)
          last_close = candles.last[:close].to_f

          if lows.size >= 2
            i1, i2 = lows.last(2)
            low1 = candles[i1][:low].to_f
            low2 = candles[i2][:low].to_f
            if low2 > low1 && last_close < low2
              return { direction: :bearish, level: low2, bar_index: i2 }
            end
          end

          if highs.size >= 2
            i1, i2 = highs.last(2)
            high1 = candles[i1][:high].to_f
            high2 = candles[i2][:high].to_f
            if high2 < high1 && last_close > high2
              return { direction: :bullish, level: high2, bar_index: i2 }
            end
          end

          nil
        end
      end
    end
  end
end
