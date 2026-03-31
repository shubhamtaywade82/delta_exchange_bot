# frozen_string_literal: true

module Trading
  # PositionRecalculator recomputes position totals from persisted fills, independent of WS arrival order.
  class PositionRecalculator
    MAX_RETRIES = 3

    def self.call(position_id)
      new(position_id).call
    end

    def initialize(position_id)
      @position_id = position_id
    end

    # Rebuilds position quantity and average entry from all related fills.
    # @return [Position]
    def call
      retries = 0

      begin
        ActiveRecord::Base.transaction(isolation: :repeatable_read) do
          position = Position.lock.find(@position_id)

          totals = Fill.joins(:order)
                       .where(orders: { position_id: position.id })
                       .select("SUM(fills.quantity) AS total_qty", "SUM(fills.quantity * fills.price) AS total_value")
                       .take

          total_qty = totals.total_qty.to_d
          total_value = totals.total_value.to_d
          avg_price = total_qty.zero? ? nil : (total_value / total_qty)

          next_state = if total_qty.zero?
                         position.orders.exists? ? "entry_pending" : "init"
                       elsif total_qty < position.orders.sum(:size).to_d
                         "partially_filled"
                       else
                         "filled"
                       end

          lot_d = Trading::Risk::PositionLotSize.multiplier_for(position).to_d

          attrs = {
            size: total_qty.zero? ? position.size : total_qty,
            entry_price: avg_price,
            status: next_state,
            needs_reconciliation: false
          }

          if lot_d.positive? && (position.contract_value.blank? || position.contract_value.to_f.zero?)
            attrs[:contract_value] = lot_d
          end

          if !total_qty.zero? && avg_price.present? && lot_d.positive?
            lev = effective_leverage(position)
            attrs[:margin] = (total_qty.abs * lot_d * avg_price.to_d.abs) / lev if lev.positive?
          end

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
