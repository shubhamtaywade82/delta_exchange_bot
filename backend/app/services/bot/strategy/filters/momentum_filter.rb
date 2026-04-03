# frozen_string_literal: true

module Bot
  module Strategy
    module Filters
      module MomentumFilter
        def self.check(side, rsi_result, logger: nil)
          return { passed: true, reason: "RSI unavailable — skipping gate" } if rsi_result.nil? || rsi_result[:value].nil?

          val = rsi_result[:value]

          if side == :long && rsi_result[:overbought]
            res = { passed: false, reason: "RSI #{val} overbought — blocking long entry" }
            Bot::StructuredLog.log(logger, :info, "filter_skip_momentum", **res)
            return res
          end

          if side == :short && rsi_result[:oversold]
            res = { passed: false, reason: "RSI #{val} oversold — blocking short entry" }
            Bot::StructuredLog.log(logger, :info, "filter_skip_momentum", **res)
            return res
          end

          { passed: true, reason: "RSI #{val} neutral" }
        end
      end
    end
  end
end
