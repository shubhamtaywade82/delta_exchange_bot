# frozen_string_literal: true

require "bigdecimal/util"

module PaperTrading
  class RrCalculator
    def self.call(side:, entry_price:, stop_price:, target_profit_pct: 0.10.to_d)
      entry = entry_price.to_d
      stop  = stop_price.to_d
      tp_pct = target_profit_pct.to_d

      target =
        case side.to_sym
        when :buy, :long
          entry * (1.to_d + tp_pct)
        when :sell, :short
          entry * (1.to_d - tp_pct)
        else
          raise ArgumentError, "invalid side: #{side}"
        end

      reward = (target - entry).abs
      risk   = (entry - stop).abs
      raise ArgumentError, "risk must be > 0" if risk <= 0

      {
        target_price: target,
        reward: reward,
        risk: risk,
        rr: reward / risk
      }
    end
  end
end
