# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Trading
  module Paper
    # Risk-budget position sizing in contract count. All money uses BigDecimal.
    class CapitalAllocator
      def initialize(equity:, risk_pct:, target_profit_pct: BigDecimal("0.1"), risk_unit_value: BigDecimal("1"))
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

        quantity = (risk_budget / per_unit_risk).floor(0)
        if quantity < 1
          return Allocation.new(
            quantity: 0,
            risk_budget: risk_budget,
            per_unit_risk: per_unit_risk,
            notional: BigDecimal("0"),
            target_price: nil,
            stop_price: stop,
            rr: nil
          )
        end

        target_price = target_for_side(side, entry)
        reward = (target_price - entry).abs * @risk_unit_value
        rr = reward / per_unit_risk
        notional = entry * quantity * @risk_unit_value

        Allocation.new(
          quantity: quantity.to_i,
          risk_budget: risk_budget,
          per_unit_risk: per_unit_risk,
          notional: notional,
          target_price: target_price,
          stop_price: stop,
          rr: rr
        )
      end

      private

      def target_for_side(side, entry)
        case side.to_s.downcase.to_sym
        when :buy, :long
          entry * (BigDecimal("1") + @target_profit_pct)
        when :sell, :short
          entry * (BigDecimal("1") - @target_profit_pct)
        else
          raise ArgumentError, "invalid side: #{side}"
        end
      end

      def bd(value)
        value.is_a?(BigDecimal) ? value : value.to_d
      end
    end
  end
end
