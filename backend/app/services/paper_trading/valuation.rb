# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module PaperTrading
  # Selects risk unit and strategy label from persisted product snapshot (DB truth).
  # Extend with per contract_type branches when Delta semantics differ.
  class Valuation
    STRATEGY_LINEAR = "contract_linear"
    STRATEGY_INVERSE = "inverse_notional"

    def self.risk_unit_per_contract(snapshot)
      return snapshot.risk_unit_per_contract.to_d if snapshot.risk_unit_per_contract.present?

      snapshot.contract_value.to_d
    end

    def self.strategy_for(snapshot)
      case snapshot.notional_type.to_s.downcase
      when "inverse"
        STRATEGY_INVERSE
      else
        snapshot.valuation_strategy.presence || STRATEGY_LINEAR
      end
    end

    def self.from_delta_product(product)
      multiplier =
        if product.respond_to?(:contract_lot_multiplier)
          product.contract_lot_multiplier
        else
          product.contract_value.to_s.to_d
        end

      notional = product.respond_to?(:notional_type) ? product.notional_type : nil
      strategy = notional.to_s.downcase == "inverse" ? STRATEGY_INVERSE : STRATEGY_LINEAR

      {
        risk_unit_per_contract: multiplier,
        valuation_strategy: strategy,
        notional_type: notional
      }
    end
  end
end
