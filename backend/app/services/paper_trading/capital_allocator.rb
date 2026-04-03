# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module PaperTrading
  class CapitalAllocator
    def initialize(equity:, risk_pct:, target_profit_pct: 0.10.to_d, risk_unit_value: 1.to_d)
      @equity = bd(equity)
      @risk_pct = bd(risk_pct)
      @target_profit_pct = bd(target_profit_pct)
      @risk_unit_value = bd(risk_unit_value)
    end

    def call(side:, entry_price:, stop_price:)
      entry = bd(entry_price)
      stop  = bd(stop_price)

      raise ArgumentError, "entry_price must be > 0" if entry <= 0
      raise ArgumentError, "stop_price must be > 0" if stop <= 0

      risk_budget = @equity * @risk_pct
      per_unit_risk = (entry - stop).abs * @risk_unit_value
      raise ArgumentError, "per_unit_risk must be > 0" if per_unit_risk <= 0

      quantity = (risk_budget / per_unit_risk).floor
      if quantity < 1
        return Allocation.new(
          quantity: 0,
          risk_budget: risk_budget,
          per_unit_risk: per_unit_risk,
          notional: 0.to_d,
          target_price: nil,
          stop_price: stop,
          rr: nil
        )
      end

      target_price = compute_target(side, entry)
      reward = (target_price - entry).abs * @risk_unit_value
      rr = reward / per_unit_risk
      notional = entry * quantity * @risk_unit_value

      Allocation.new(
        quantity: quantity,
        risk_budget: risk_budget,
        per_unit_risk: per_unit_risk,
        notional: notional,
        target_price: target_price,
        stop_price: stop,
        rr: rr
      )
    end

    private

    def compute_target(side, entry)
      case side.to_sym
      when :buy, :long
        entry * (1.to_d + @target_profit_pct)
      when :sell, :short
        entry * (1.to_d - @target_profit_pct)
      else
        raise ArgumentError, "invalid side: #{side}"
      end
    end

    def bd(value)
      value.is_a?(BigDecimal) ? value : value.to_d
    end
  end
end
