# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module OrderBlock
        def self.compute(candles, min_impulse_pct: 0.3, max_ob_age: 20)
          n   = candles.size
          obs = []

          return obs if n < 4

          (0...(n - 2)).each do |i|
            c = candles[i]

            lookahead    = candles[(i + 1)..[i + 3, n - 1].min]
            next_closes  = lookahead.map { |x| x[:close].to_f }
            impulse_up   = next_closes.all? { |cl| cl > c[:close].to_f }
            impulse_down = next_closes.all? { |cl| cl < c[:close].to_f }

            move_pct = next_closes.last ? ((next_closes.last - c[:close].to_f) / c[:close].to_f * 100).abs : 0
            next if move_pct < min_impulse_pct

            age = n - 1 - i
            next if age > max_ob_age

            last_close = candles.last[:close].to_f

            if impulse_up && c[:close].to_f < c[:open].to_f
              fresh = last_close > c[:low].to_f
              obs << { side: :bull, high: c[:high].to_f, low: c[:low].to_f,
                       age: age, fresh: fresh, strength: move_pct.round(2) }
            elsif impulse_down && c[:close].to_f > c[:open].to_f
              fresh = last_close < c[:high].to_f
              obs << { side: :bear, high: c[:high].to_f, low: c[:low].to_f,
                       age: age, fresh: fresh, strength: move_pct.round(2) }
            end
          end

          obs.sort_by { |ob| ob[:age] }
        end
      end
    end
  end
end
