# frozen_string_literal: true

module Bot
  module Strategy
    module Filters
      module VolumeFilter
        def self.check(side, cvd_data, current_price, vwap_result)
          return { passed: true, reason: "CVD/VWAP unavailable — skipping gate" } if cvd_data.nil? || vwap_result.nil?

          cvd_trend   = cvd_data[:delta_trend]
          price_above = vwap_result[:price_above]
          vwap_val    = vwap_result[:vwap]

          if side == :long
            unless cvd_trend == :bullish
              return { passed: false, reason: "CVD #{cvd_trend} — does not support long entry" }
            end
            unless price_above
              return { passed: false, reason: "VWAP #{vwap_val}: price #{current_price} below VWAP — blocking long" }
            end
          else
            unless cvd_trend == :bearish
              return { passed: false, reason: "CVD #{cvd_trend} — does not support short entry" }
            end
            if price_above
              return { passed: false, reason: "VWAP #{vwap_val}: price #{current_price} above VWAP — blocking short" }
            end
          end

          { passed: true, reason: "CVD #{cvd_trend}, price #{side == :long ? 'above' : 'below'} VWAP #{vwap_val}" }
        end
      end
    end
  end
end
