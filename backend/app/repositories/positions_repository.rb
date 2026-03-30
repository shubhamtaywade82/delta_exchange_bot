# frozen_string_literal: true

module PositionsRepository
  def self.open_for(symbol)
    Position.active.find_by(symbol: symbol)
  end

  def self.upsert_from_order(order)
    position = Position.active.find_or_initialize_by(symbol: order.symbol)
    position.assign_attributes(
      side:        order.side == "buy" ? "long" : "short",
      size:        order.filled_qty,
      entry_price: order.avg_fill_price,
      status:      "filled"
    )
    position.entry_time ||= Time.current
    position.save!
    position
  end

  def self.close!(symbol)
    Position.active.where(symbol: symbol).update_all(
      status: "closed", exit_time: Time.current
    )
  end
end
