# frozen_string_literal: true

module Bot
  module Strategy
    # Classic Supertrend (ATR bands + trailing stop).
    # ATR uses Wilder's smoothing with a proper SMA seed at bar (period - 1).
    # Bar 0 initializes final upper/lower from hl2 ± mult×ATR (not zero), so early
    # carry-forward matches TradingView-style implementations.
    module Supertrend
      module_function

      def compute(candles, atr_period:, multiplier:)
        raise ArgumentError, "Need at least 2 candles" if candles.size < 2
        raise ArgumentError, "atr_period must be positive" if atr_period < 1

        n = candles.size
        results = Array.new(n) { { direction: nil, line: nil } }

        tr = build_true_range(candles)
        atr = build_atr_series(tr, atr_period)

        upper = Array.new(n)
        lower = Array.new(n)
        dir   = Array.new(n, :bullish)

        hl2_0 = (candles[0][:high].to_f + candles[0][:low].to_f) / 2.0
        upper[0] = hl2_0 + multiplier * atr[0]
        lower[0] = hl2_0 - multiplier * atr[0]

        (1...n).each do |i|
          c  = candles[i]
          cp = candles[i - 1]

          hl2 = (c[:high].to_f + c[:low].to_f) / 2.0

          basic_upper = hl2 + multiplier * atr[i]
          basic_lower = hl2 - multiplier * atr[i]

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

      def build_true_range(candles)
        n = candles.size
        Array.new(n) do |i|
          c = candles[i]
          if i.zero?
            c[:high].to_f - c[:low].to_f
          else
            cp = candles[i - 1]
            [
              c[:high].to_f - c[:low].to_f,
              (c[:high].to_f - cp[:close].to_f).abs,
              (c[:low].to_f - cp[:close].to_f).abs
            ].max
          end
        end
      end

      def build_atr_series(tr, period)
        n = tr.size
        atr = Array.new(n)

        if period <= 1
          n.times { |i| atr[i] = tr[i].to_f }
          return atr
        end

        atr[0] = tr[0].to_f
        (1...n).each do |i|
          atr[i] = if i < period - 1
                     tr[0..i].sum / (i + 1).to_f
                   elsif i == period - 1
                     tr[0..i].sum / period.to_f
                   else
                     (atr[i - 1] * (period - 1) + tr[i]) / period.to_f
                   end
        end
        atr
      end
    end
  end
end
