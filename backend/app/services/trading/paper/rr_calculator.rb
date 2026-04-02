# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Trading
  module Paper
    class RrCalculator
      Result = Struct.new(:target_price, :reward, :risk, :rr, keyword_init: true)

      def self.call(side:, entry_price:, stop_price:, target_profit_pct: BigDecimal("0.1"))
        entry = entry_price.to_d
        stop  = stop_price.to_d
        tp_pct = target_profit_pct.to_d

        target =
          case side.to_s.downcase.to_sym
          when :buy, :long
            entry * (BigDecimal("1") + tp_pct)
          when :sell, :short
            entry * (BigDecimal("1") - tp_pct)
          else
            raise ArgumentError, "invalid side: #{side}"
          end

        reward = (target - entry).abs
        risk   = (entry - stop).abs
        raise ArgumentError, "risk must be > 0" if risk <= 0

        Result.new(
          target_price: target,
          reward: reward,
          risk: risk,
          rr: reward / risk
        )
      end
    end
  end
end
