# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module RSI
        def self.compute(candles, period: 14)
          n       = candles.size
          results = Array.new(n) { { value: nil, overbought: false, oversold: false } }
          return results if n <= period

          changes = (1...n).map { |i| candles[i][:close].to_f - candles[i - 1][:close].to_f }

          avg_gain = changes[0, period].sum { |c| c > 0 ? c : 0.0 } / period
          avg_loss = changes[0, period].sum { |c| c < 0 ? c.abs : 0.0 } / period

          results[period] = build_result(avg_gain, avg_loss)

          (period...(changes.size)).each do |i|
            avg_gain = (avg_gain * (period - 1) + [changes[i], 0.0].max) / period
            avg_loss = (avg_loss * (period - 1) + [(-changes[i]), 0.0].max) / period
            results[i + 1] = build_result(avg_gain, avg_loss)
          end

          results
        end

        def self.build_result(avg_gain, avg_loss)
          rsi = avg_loss.zero? ? 100.0 : 100.0 - (100.0 / (1.0 + avg_gain / avg_loss))
          { value: rsi.round(2), overbought: rsi > 70, oversold: rsi < 30 }
        end
        private_class_method :build_result
      end
    end
  end
end
