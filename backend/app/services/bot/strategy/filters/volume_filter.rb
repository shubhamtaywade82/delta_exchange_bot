# frozen_string_literal: true

module Bot
  module Strategy
    module Filters
      module VolumeFilter
        def self.check(side, cvd_data, current_price, vwap_result, logger: nil)
          return { passed: true, reason: "CVD/VWAP unavailable — skipping gate" } if cvd_data.nil? || vwap_result.nil?

          cvd_trend   = cvd_data[:delta_trend]
          price_above = vwap_result[:price_above]
          vwap_val    = vwap_result[:vwap]

          if side == :long
            unless cvd_trend == :bullish
              res = { passed: false, reason: "CVD #{cvd_trend} — does not support long entry" }
              Bot::StructuredLog.log(logger, :info, "filter_skip_volume", **res)
              return res
            end
            unless price_above
              res = { passed: false, reason: "VWAP #{vwap_val}: price #{current_price} below VWAP — blocking long" }
              Bot::StructuredLog.log(logger, :info, "filter_skip_volume", **res)
              return res
            end
          else
            unless cvd_trend == :bearish
              res = { passed: false, reason: "CVD #{cvd_trend} — does not support short entry" }
              Bot::StructuredLog.log(logger, :info, "filter_skip_volume", **res)
              return res
            end
            if price_above
              res = { passed: false, reason: "VWAP #{vwap_val}: price #{current_price} above VWAP — blocking short" }
              Bot::StructuredLog.log(logger, :info, "filter_skip_volume", **res)
              return res
            end
          end

          { passed: true, reason: "CVD #{cvd_trend}, price #{side == :long ? 'above' : 'below'} VWAP #{vwap_val}" }
        end
      end
    end
  end
end
