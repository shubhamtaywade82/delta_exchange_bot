# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Trading
  module Paper
    # Per-contract multiplier for linear-style products (aligns with PositionLotSize / Delta product metadata).
    module RiskUnitValue
      module_function

      def for_symbol(symbol)
        sym = symbol.to_s.strip
        return BigDecimal("1") if sym.blank?

        config = SymbolConfig.find_by(symbol: sym)
        if config&.metadata.is_a?(Hash)
          raw = config.metadata["contract_lot_multiplier"] || config.metadata[:contract_lot_multiplier]
          return BigDecimal(raw.to_s) if raw.present? && BigDecimal(raw.to_s).positive?
        end

        BigDecimal(Trading::Risk::PositionLotSize.from_exchange(sym).to_s)
      end
    end
  end
end
