# frozen_string_literal: true

module Trading
  # Recomputes net position from all fills for (portfolio, symbol); updates wallet-related fields.
  class PositionRecalculator
    MAX_RETRIES = 3

    def self.call(position_id)
      new(position_id).call
    end

    def initialize(position_id)
      @position_id = position_id
    end

    # @return [Position]
    def call
      retries = 0

      begin
        ActiveRecord::Base.transaction(isolation: :repeatable_read) do
          position = Position.lock.find(@position_id)

          fills = Fill.joins(:order)
                      .where(orders: { portfolio_id: position.portfolio_id, symbol: position.symbol })
                      .to_a

          calc = Trading::Ledger::NetPositionCalculator.from_fills(fills)
          q = calc.signed_qty
          lot_d = Trading::Risk::PositionLotSize.multiplier_for(position).to_d

          next_state = derive_status(position, q, fills)
          mark = Trading::MarkPrice.for_symbol(position.symbol) || calc.avg_entry

          attrs = base_attrs(q, calc, lot_d, next_state, position, mark)
          position.update!(attrs)

          position
        end
      rescue ActiveRecord::StaleObjectError
        retries += 1
        retry if retries < MAX_RETRIES
        raise
      end
    end

    private

    def base_attrs(q, calc, lot_d, next_state, position, mark)
      if q.zero?
        return {
          size: 0,
          side: position.side,
          entry_price: nil,
          margin: nil,
          unrealized_pnl_usd: 0,
          status: next_state,
          needs_reconciliation: false
        }
      end

      avg = calc.avg_entry
      lev = effective_leverage(position)
      margin = if lev.positive? && lot_d.positive? && avg.present?
                 (q.abs * lot_d * avg.abs) / lev
               end

      side = q.positive? ? "long" : "short"
      position.assign_attributes(size: q.abs, side: side, entry_price: avg, margin: margin)

      unrealized = Trading::Risk::PositionRisk.call(position: position, mark_price: mark).unrealized_pnl

      attrs = {
        size: q.abs,
        side: side,
        entry_price: avg,
        margin: margin,
        unrealized_pnl_usd: unrealized,
        status: next_state,
        needs_reconciliation: false
      }

      attrs[:contract_value] = lot_d if lot_d.positive? && (position.contract_value.blank? || position.contract_value.to_f.zero?)
      attrs
    end

    def derive_status(position, signed_qty, fills)
      pending_orders = Order.where(portfolio_id: position.portfolio_id, symbol: position.symbol)
                            .where(status: %w[created submitted partially_filled])

      if signed_qty.zero?
        return "entry_pending" if pending_orders.exists?

        return fills.any? ? "closed" : "init"
      end

      pending_orders.exists? ? "partially_filled" : "filled"
    end

    def effective_leverage(position)
      lev = position.leverage.to_d
      return lev if lev.positive?

      picked = Order.where(position_id: position.id)
                    .joins(:trading_session)
                    .limit(1)
                    .pick("trading_sessions.leverage")
      lev = picked.to_d
      return lev if lev.positive?

      1.to_d
    end
  end
end
