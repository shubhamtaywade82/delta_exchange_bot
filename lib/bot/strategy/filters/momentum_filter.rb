# frozen_string_literal: true

module Bot
  module Strategy
    module Filters
      module MomentumFilter
        def self.check(side, rsi_result)
          return { passed: true, reason: "RSI unavailable — skipping gate" } if rsi_result.nil? || rsi_result[:value].nil?

          val = rsi_result[:value]

          if side == :long && rsi_result[:overbought]
            return { passed: false, reason: "RSI #{val} overbought — blocking long entry" }
          end

          if side == :short && rsi_result[:oversold]
            return { passed: false, reason: "RSI #{val} oversold — blocking short entry" }
          end

          { passed: true, reason: "RSI #{val} neutral" }
        end
      end
    end
  end
end
