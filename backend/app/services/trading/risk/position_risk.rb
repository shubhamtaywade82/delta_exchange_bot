# frozen_string_literal: true

module Trading
  module Risk
    # PositionRisk computes live PnL and notional exposure for a position.
    class PositionRisk
      Result = Struct.new(:unrealized_pnl, :realized_pnl, :notional, keyword_init: true)

      # @param position [Position]
      # @param mark_price [Numeric]
      # @return [Result]
      def self.call(position:, mark_price:)
        qty = position.size.to_d.abs
        return zero_result if qty.zero?

        entry = position.entry_price.to_d
        direction = position.side.in?(%w[sell short]) ? -1.to_d : 1.to_d
        unrealized = (mark_price.to_d - entry) * qty * direction

        Result.new(
          unrealized_pnl: unrealized,
          realized_pnl: position.pnl_usd.to_d,
          notional: qty * mark_price.to_d
        )
      end

      def self.zero_result
        Result.new(unrealized_pnl: 0.to_d, realized_pnl: 0.to_d, notional: 0.to_d)
      end
    end
  end
end
