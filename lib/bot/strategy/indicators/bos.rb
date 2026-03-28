# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module BOS
        def self.compute(candles, swing_lookback: 10)
          n       = candles.size
          results = Array.new(n) { { direction: nil, level: nil, confirmed: false } }

          (swing_lookback...n).each do |i|
            window      = candles[(i - swing_lookback)...i]
            swing_high  = window.map { |c| c[:high].to_f }.max
            swing_low   = window.map { |c| c[:low].to_f  }.min
            close       = candles[i][:close].to_f

            if close > swing_high
              results[i] = { direction: :bullish, level: swing_high, confirmed: true }
            elsif close < swing_low
              results[i] = { direction: :bearish, level: swing_low, confirmed: true }
            else
              prev = results[i - 1]
              results[i] = { direction: prev[:direction], level: prev[:level], confirmed: false }
            end
          end

          results
        end
      end
    end
  end
end
