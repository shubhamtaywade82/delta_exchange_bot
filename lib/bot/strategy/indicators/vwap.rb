# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module VWAP
        def self.compute(candles, session_reset_hour_utc: 0)
          n        = candles.size
          results  = Array.new(n) { { vwap: nil, deviation_pct: nil, price_above: nil } }
          cum_tpv  = 0.0
          cum_vol  = 0.0

          candles.each_with_index do |c, i|
            if i > 0
              ts      = Time.at(c[:timestamp].to_i).utc
              prev_ts = Time.at(candles[i - 1][:timestamp].to_i).utc
              if ts.hour == session_reset_hour_utc && prev_ts.hour != session_reset_hour_utc
                cum_tpv = 0.0
                cum_vol = 0.0
              end
            end

            vol = c[:volume].to_f
            next if vol.zero?

            typical = (c[:high].to_f + c[:low].to_f + c[:close].to_f) / 3.0
            cum_tpv += typical * vol
            cum_vol  += vol

            vwap = cum_tpv / cum_vol
            dev  = ((c[:close].to_f - vwap) / vwap * 100.0).round(4)

            results[i] = {
              vwap:          vwap.round(4),
              deviation_pct: dev,
              price_above:   c[:close].to_f >= vwap
            }
          end

          results
        end
      end
    end
  end
end
