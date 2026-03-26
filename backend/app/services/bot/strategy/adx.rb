# frozen_string_literal: true

module Bot
  module Strategy
    module ADX
      def self.compute(candles, period:)
        n       = candles.size
        results = Array.new(n) { { adx: nil, plus_di: nil, minus_di: nil } }

        return results if n < period * 2

        tr_arr       = Array.new(n, 0.0)
        plus_dm_arr  = Array.new(n, 0.0)
        minus_dm_arr = Array.new(n, 0.0)

        (1...n).each do |i|
          c  = candles[i]
          cp = candles[i - 1]

          up_move   = c[:high].to_f - cp[:high].to_f
          down_move = cp[:low].to_f  - c[:low].to_f

          plus_dm_arr[i]  = up_move > down_move && up_move > 0 ? up_move : 0.0
          minus_dm_arr[i] = down_move > up_move && down_move > 0 ? down_move : 0.0

          tr_arr[i] = [
            c[:high].to_f - c[:low].to_f,
            (c[:high].to_f - cp[:close].to_f).abs,
            (c[:low].to_f  - cp[:close].to_f).abs
          ].max
        end

        # Seed Wilder smoothing with sum of first `period` values
        s_tr       = tr_arr[1..period].sum
        s_plus_dm  = plus_dm_arr[1..period].sum
        s_minus_dm = minus_dm_arr[1..period].sum

        dx_arr = []

        plus_di  = 100.0 * s_plus_dm  / s_tr
        minus_di = 100.0 * s_minus_dm / s_tr
        dx_arr << (100.0 * (plus_di - minus_di).abs / (plus_di + minus_di)) if (plus_di + minus_di).positive?

        ((period + 1)...n).each do |i|
          s_tr       = s_tr       - (s_tr       / period) + tr_arr[i]
          s_plus_dm  = s_plus_dm  - (s_plus_dm  / period) + plus_dm_arr[i]
          s_minus_dm = s_minus_dm - (s_minus_dm / period) + minus_dm_arr[i]

          plus_di  = 100.0 * s_plus_dm  / s_tr
          minus_di = 100.0 * s_minus_dm / s_tr

          dx = if (plus_di + minus_di).positive?
                 100.0 * (plus_di - minus_di).abs / (plus_di + minus_di)
               else
                 0.0
               end
          dx_arr << dx

          next if dx_arr.size < period

          adx = if dx_arr.size == period
                  dx_arr.sum / period
                else
                  (results[i - 1][:adx] * (period - 1) + dx) / period
                end

          results[i] = { adx: adx.round(4), plus_di: plus_di.round(4), minus_di: minus_di.round(4) }
        end

        results
      end
    end
  end
end
