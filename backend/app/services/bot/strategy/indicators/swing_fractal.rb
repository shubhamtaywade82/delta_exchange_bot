# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module SwingFractal
        module_function

        def pivot_low_indices(candles, left:, right:)
          return [] if candles.size <= left + right

          (left...(candles.size - right)).each_with_object([]) do |i, acc|
            l = candles[i][:low].to_f
            left_ok = (i - left...i).all? { |j| candles[j][:low].to_f > l }
            right_ok = (i + 1..i + right).all? { |j| candles[j][:low].to_f >= l }
            acc << i if left_ok && right_ok
          end
        end

        def pivot_high_indices(candles, left:, right:)
          return [] if candles.size <= left + right

          (left...(candles.size - right)).each_with_object([]) do |i, acc|
            h = candles[i][:high].to_f
            left_ok = (i - left...i).all? { |j| candles[j][:high].to_f < h }
            right_ok = (i + 1..i + right).all? { |j| candles[j][:high].to_f <= h }
            acc << i if left_ok && right_ok
          end
        end
      end
    end
  end
end
