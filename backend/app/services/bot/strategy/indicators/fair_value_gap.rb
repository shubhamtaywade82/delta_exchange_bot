# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module FairValueGap
        def self.detect(candles, max_age: 30)
          n = candles.size
          return [] if n < 3

          fvgs = []
          (0...(n - 2)).each do |i|
            a = candles[i]
            c = candles[i + 2]
            age = n - 1 - (i + 2)
            next if age > max_age

            a_high = a[:high].to_f
            a_low = a[:low].to_f
            c_high = c[:high].to_f
            c_low = c[:low].to_f

            if c_low > a_high
              fvgs << {
                type: :bullish,
                top: c_low,
                bottom: a_high,
                formed_bar: i + 1,
                age_bars: age
              }
            elsif c_high < a_low
              fvgs << {
                type: :bearish,
                top: a_low,
                bottom: c_high,
                formed_bar: i + 1,
                age_bars: age
              }
            end
          end

          fvgs
        end
      end
    end
  end
end
