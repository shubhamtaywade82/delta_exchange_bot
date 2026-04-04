# frozen_string_literal: true

require_relative "../indicator_service"

module Bot
  module Strategy
    module Indicators
      module RSI
        def self.compute(candles, period: 14)
          rsi_values = IndicatorService.rsi(candles, period: period)

          # Maintain existing format: array of hashes with overbought/oversold flags
          # Note: gems usually return fewer results than input size due to the period,
          # but IndicatorService/gems handle padding or starting after the period.
          # Here we pad with nil results for consistency if needed,
          # but technical-analysis gem returns results starting after the first period-1 entries.

          results = Array.new(candles.size) { { value: nil, overbought: false, oversold: false } }

          # Align results. technical-analysis gem returns an array of length candles.size - period.
          # We place them at the end of the results array.
          offset = candles.size - rsi_values.size

          rsi_values.each_with_index do |val, i|
            results[offset + i] = {
              value: val.round(2),
              overbought: val > 70,
              oversold: val < 30
            }
          end

          results
        end
      end
    end
  end
end
