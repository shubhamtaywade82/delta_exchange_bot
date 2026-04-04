# frozen_string_literal: true

module Bot
  module Strategy
    # ML Adaptive SuperTrend — volatility-regime clustering on ATR (RMA), Pine-style bands.
    # Ported from algo_scalper_api app/services/indicators/ml_adaptive_supertrend.rb
    module MlAdaptiveSupertrend
      module_function

      def compute(candles, atr_len:, factor:, training_period:, highvol: 0.75, midvol: 0.5, lowvol: 0.25)
        raise ArgumentError, "Need at least 2 candles" if candles.size < 2

        highs  = candles.map { |c| c[:high].to_f }
        lows   = candles.map { |c| c[:low].to_f }
        closes = candles.map { |c| c[:close].to_f }
        n = closes.size

        atr = calculate_rma_atr(highs, lows, closes, atr_len)
        upper_vol = rolling_highest(atr, training_period)
        lower_vol = rolling_lowest(atr, training_period)

        super_trend = Array.new(n)
        direction = Array.new(n)
        upper_band = Array.new(n)
        lower_band = Array.new(n)

        n.times do |i|
          if i < atr_len || atr[i].nil? || upper_vol[i].nil? || lower_vol[i].nil?
            direction[i] = nil
            next
          end

          hv = lower_vol[i] + ((upper_vol[i] - lower_vol[i]) * highvol)
          mv = lower_vol[i] + ((upper_vol[i] - lower_vol[i]) * midvol)
          lv = lower_vol[i] + ((upper_vol[i] - lower_vol[i]) * lowvol)

          dist_h = (atr[i] - hv).abs
          dist_m = (atr[i] - mv).abs
          dist_l = (atr[i] - lv).abs

          cluster = if dist_h < dist_m && dist_h < dist_l
                      0
          elsif dist_m < dist_l
                      1
          else
                      2
          end

          a_atr = case cluster
          when 0 then hv
          when 1 then mv
          else lv
          end

          hl2 = (highs[i] + lows[i]) / 2.0
          b_upper = hl2 + (factor * a_atr)
          b_lower = hl2 - (factor * a_atr)

          if i.zero? || upper_band[i - 1].nil? || lower_band[i - 1].nil?
            upper_band[i] = b_upper
            lower_band[i] = b_lower
            direction[i] = (closes[i] > b_upper ? -1 : 1)
          else
            prev_upper = upper_band[i - 1]
            prev_lower = lower_band[i - 1]
            prev_close = closes[i - 1]
            prev_dir = direction[i - 1]

            upper_band[i] = b_upper < prev_upper || prev_close > prev_upper ? b_upper : prev_upper
            lower_band[i] = b_lower > prev_lower || prev_close < prev_lower ? b_lower : prev_lower

            prev_st = (prev_dir == -1 ? prev_lower : prev_upper)

            direction[i] = if prev_st == prev_upper
                           (closes[i] > upper_band[i] ? -1 : 1)
            else
                           (closes[i] < lower_band[i] ? 1 : -1)
            end
          end

          super_trend[i] = (direction[i] == -1 ? lower_band[i] : upper_band[i])
        end

        Array.new(n) do |i|
          d = direction[i]
          if d.nil? || super_trend[i].nil?
            { direction: nil, line: nil }
          else
            { direction: (d == -1 ? :bullish : :bearish), line: super_trend[i] }
          end
        end
      end

      def calculate_rma_atr(highs, lows, closes, length)
        size = closes.size
        tr = Array.new(size)
        atr = Array.new(size)

        size.times do |i|
          tr[i] = if i.zero?
                    highs[i] - lows[i]
          else
                    [
                      highs[i] - lows[i],
                      (highs[i] - closes[i - 1]).abs,
                      (lows[i] - closes[i - 1]).abs
                    ].max
          end
        end

        rma_sum = 0.0
        size.times do |i|
          if i < length - 1
            rma_sum += tr[i]
            atr[i] = nil
          elsif i == length - 1
            rma_sum += tr[i]
            atr[i] = rma_sum / length
          else
            atr[i] = ((atr[i - 1] * (length - 1)) + tr[i]) / length.to_f
          end
        end

        atr
      end

      def rolling_highest(source, length)
        rolling_extremum(source, length, :max)
      end

      def rolling_lowest(source, length)
        rolling_extremum(source, length, :min)
      end

      def rolling_extremum(source, length, mode)
        size = source.size
        results = Array.new(size)

        size.times do |i|
          if i < length - 1
            results[i] = nil
          else
            window = source[(i - length + 1)..i].compact
            results[i] = window.empty? ? nil : window.send(mode)
          end
        end

        results
      end
    end
  end
end
