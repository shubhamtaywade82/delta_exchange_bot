# frozen_string_literal: true

module OrdersRepository
  def self.create!(attrs)
    Order.create!(attrs)
  end

  def self.find_by_exchange_id(exchange_order_id)
    Order.find_by(exchange_order_id: exchange_order_id)
  end

  def self.update_from_fill(exchange_order_id:, filled_qty:, avg_fill_price:, status:)
    order = find_by_exchange_id(exchange_order_id)
    return unless order

    order.update!(
      filled_qty:     filled_qty,
      avg_fill_price: avg_fill_price,
      status:         status
    )
    order
  end
end
