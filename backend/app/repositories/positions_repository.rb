# frozen_string_literal: true

module PositionsRepository
  def self.open_for(symbol)
    Position.find_by(symbol: symbol, status: "open")
  end

  def self.upsert_from_order(order)
    position = Position.find_or_initialize_by(symbol: order.symbol, status: "open")
    position.assign_attributes(
      side:        order.side == "buy" ? "long" : "short",
      size:        order.filled_qty,
      entry_price: order.avg_fill_price,
      status:      "open"
    )
    position.entry_time ||= Time.current
    position.save!
    position
  end

  def self.close!(symbol)
    Position.where(symbol: symbol, status: "open").update_all(
      status: "closed", exit_time: Time.current
    )
  end
end
