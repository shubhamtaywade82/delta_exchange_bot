# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module PaperTrading
  class PnlCalculator
    def self.call(side:, entry_price:, exit_price:, quantity:, risk_unit_value: 1.to_d, fees: 0.to_d)
      entry = bd(entry_price)
      exitp = bd(exit_price)
      qty   = bd(quantity)
      unit  = bd(risk_unit_value)
      fee   = bd(fees)

      gross =
        case side.to_sym
        when :buy, :long
          (exitp - entry) * qty * unit
        when :sell, :short
          (entry - exitp) * qty * unit
        else
          raise ArgumentError, "invalid side: #{side}"
        end

      net = gross - fee
      { gross_pnl: gross, net_pnl: net, fees: fee }
    end

    def self.realized_for_partial_fills(side:, fills:, entry_avg:, risk_unit_value: 1.to_d, fees: 0.to_d)
      exit_price = weighted_avg(fills)
      total_qty = fills.sum { |f| bd(f[:size]) }
      call(
        side: side,
        entry_price: entry_avg,
        exit_price: exit_price,
        quantity: total_qty,
        risk_unit_value: risk_unit_value,
        fees: fees
      )
    end

    def self.weighted_avg(fills)
      total_qty = fills.sum { |f| bd(f[:size]) }
      return 0.to_d if total_qty <= 0

      total_value = fills.sum { |f| bd(f[:price]) * bd(f[:size]) }
      total_value / total_qty
    end

    def self.bd(value)
      value.is_a?(BigDecimal) ? value : value.to_d
    end
    private_class_method :bd
  end
end
