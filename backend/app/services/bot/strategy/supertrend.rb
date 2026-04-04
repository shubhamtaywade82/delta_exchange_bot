# frozen_string_literal: true

module Bot
  module Strategy
    module Supertrend
      def self.compute(candles, atr_period:, multiplier:)
        raise ArgumentError, "Need at least 2 candles" if candles.size < 2

        n       = candles.size
        results = Array.new(n) { { direction: nil, line: nil } }

        atr     = Array.new(n, 0.0)
        upper   = Array.new(n, 0.0)
        lower   = Array.new(n, 0.0)
        dir     = Array.new(n, :bullish)

        # First bar — seed ATR
        atr[0] = candles[0][:high].to_f - candles[0][:low].to_f

        (1...n).each do |i|
          c  = candles[i]
          cp = candles[i - 1]

          tr = [
            c[:high].to_f  - c[:low].to_f,
            (c[:high].to_f  - cp[:close].to_f).abs,
            (c[:low].to_f   - cp[:close].to_f).abs
          ].max

          # Wilder's smoothing
          atr[i] = (atr[i - 1] * (atr_period - 1) + tr) / atr_period

          hl2 = (c[:high].to_f + c[:low].to_f) / 2.0

          basic_upper = hl2 + multiplier * atr[i]
          basic_lower = hl2 - multiplier * atr[i]

          # Band carry-forward (prevents band from moving away from price)
          upper[i] = if basic_upper < upper[i - 1] || cp[:close].to_f > upper[i - 1]
                       basic_upper
          else
                       upper[i - 1]
          end

          lower[i] = if basic_lower > lower[i - 1] || cp[:close].to_f < lower[i - 1]
                       basic_lower
          else
                       lower[i - 1]
          end

          close = c[:close].to_f

          dir[i] = if dir[i - 1] == :bearish && close > upper[i - 1]
                     :bullish
          elsif dir[i - 1] == :bullish && close < lower[i - 1]
                     :bearish
          else
                     dir[i - 1]
          end

          next if i < atr_period

          results[i] = {
            direction: dir[i],
            line: dir[i] == :bullish ? lower[i] : upper[i]
          }
        end

        results
      end
    end
  end
end
