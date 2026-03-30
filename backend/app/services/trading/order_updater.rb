# frozen_string_literal: true

module Trading
  # OrderUpdater applies exchange order lifecycle updates under lock.
  class OrderUpdater
    def self.process(event)
      new(event).process
    end

    def initialize(event)
      @event = event
    end

    # Applies order status updates from exchange.
    # @return [Order, nil]
    def process
      order = Order.find_by(client_order_id: @event.client_order_id) ||
              Order.find_by(exchange_order_id: @event.exchange_order_id)
      return nil unless order

      order.with_lock do
        order.update!(exchange_order_id: @event.exchange_order_id) if @event.exchange_order_id.present? && order.exchange_order_id.blank?

        target_state = normalize_status(@event.status)
        if order.status == "created" && target_state.in?(%w[partially_filled filled])
          order.transition_to!("submitted")
        end
        order.transition_to!(target_state) if target_state != order.status

        if @event.filled_qty.present?
          order.apply_fill!(
            cumulative_qty: @event.filled_qty,
            avg_fill_price: @event.avg_fill_price,
            exchange_status: @event.status
          )
        end
      end

      order.position&.recalculate_from_orders!
      order
    end

    private

    def normalize_status(status)
      case status.to_s
      when "open", "pending", "submitted" then "submitted"
      when "partially_filled" then "partially_filled"
      when "filled" then "filled"
      when "cancelled", "canceled" then "cancelled"
      when "rejected" then "rejected"
      else "submitted"
      end
    end
  end
end
