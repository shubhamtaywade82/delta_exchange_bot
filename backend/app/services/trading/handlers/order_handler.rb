# frozen_string_literal: true

module Trading
  module Handlers
    class OrderHandler
      def initialize(event)
        @event = event
      end

      def call
        order = update_order_status
        return unless order&.filled?

        update_position(order)
        create_trade_if_closing(order)
        EventBus.publish(:position_updated, build_position_event(order))
      rescue => e
        Rails.logger.error("[OrderHandler] Error processing fill #{@event.exchange_order_id}: #{e.message}")
      end

      private

      def update_order_status
        OrdersRepository.update_from_fill(
          exchange_order_id: @event.exchange_order_id,
          filled_qty:        @event.filled_qty,
          avg_fill_price:    @event.avg_fill_price,
          status:            @event.status
        )
      end

      def update_position(order)
        if order.side == "buy"
          PositionsRepository.upsert_from_order(order)
        else
          PositionsRepository.close!(order.symbol)
        end
      end

      def create_trade_if_closing(order)
        return if order.side == "buy"

        entry_position = PositionsRepository.open_for(order.symbol)
        return unless entry_position

        pnl = calculate_pnl(entry_position, order)
        Trade.create!(
          symbol:           order.symbol,
          side:             entry_position.side,
          size:             order.filled_qty,
          entry_price:      entry_position.entry_price,
          exit_price:       order.avg_fill_price,
          pnl_usd:          pnl,
          pnl_inr:          pnl * usd_to_inr_rate,
          duration_seconds: (Time.current - entry_position.entry_time.to_time).to_i,
          closed_at:        Time.current
        )
      end

      def calculate_pnl(position, order)
        multiplier = position.side == "long" ? 1 : -1
        (order.avg_fill_price - position.entry_price) * order.filled_qty * multiplier
      end

      def usd_to_inr_rate
        Setting.find_by(key: "usd_to_inr_rate")&.value&.to_f || 85.0
      end

      def build_position_event(order)
        pos = Position.find_by(symbol: order.symbol)
        Events::PositionUpdated.new(
          symbol:        order.symbol,
          side:          pos&.side || "unknown",
          size:          order.filled_qty,
          entry_price:   pos&.entry_price || 0,
          mark_price:    Rails.cache.read("ltp:#{order.symbol}").to_f,
          unrealized_pnl: 0.0,
          status:        pos&.status || "closed"
        )
      end
    end
  end
end
