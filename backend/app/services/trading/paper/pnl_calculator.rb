# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Trading
  module Paper
    class PnlCalculator
      Result = Struct.new(:gross_pnl, :net_pnl, :fees, keyword_init: true)

      def self.call(side:, entry_price:, exit_price:, quantity:, risk_unit_value: BigDecimal("1"), fees: BigDecimal("0"))
        entry = to_bd(entry_price)
        exitp = to_bd(exit_price)
        qty   = to_bd(quantity)
        unit  = to_bd(risk_unit_value)
        fee   = to_bd(fees)

        gross =
          case side.to_s.downcase.to_sym
          when :buy, :long
            (exitp - entry) * qty * unit
          when :sell, :short
            (entry - exitp) * qty * unit
          else
            raise ArgumentError, "invalid side: #{side}"
          end

        net = gross - fee
        Result.new(gross_pnl: gross, net_pnl: net, fees: fee)
      end

      def self.realized_for_partial_fills(side:, fills:, entry_avg:, risk_unit_value: BigDecimal("1"), fees: BigDecimal("0"))
        exit_price = weighted_avg_price(fills)
        total_qty = fills.sum { |f| to_bd(f[:size] || f[:quantity]) }
        call(
          side: side,
          entry_price: entry_avg,
          exit_price: exit_price,
          quantity: total_qty,
          risk_unit_value: risk_unit_value,
          fees: fees
        )
      end

      def self.weighted_avg_price(fills)
        total_qty = fills.sum { |f| to_bd(f[:size] || f[:quantity]) }
        return BigDecimal("0") if total_qty <= 0

        total_value = fills.sum { |f| to_bd(f[:price]) * to_bd(f[:size] || f[:quantity]) }
        total_value / total_qty
      end

      def self.to_bd(value)
        value.is_a?(BigDecimal) ? value : value.to_d
      end
      private_class_method :to_bd
    end
  end
end
