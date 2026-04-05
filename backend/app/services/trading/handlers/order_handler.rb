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

        closing_entry = PositionsRepository.snapshot_for_closing_trade(order)
        PositionsRepository.apply_fill_from_order!(order, closing: closing_entry.present?)
        create_trade_if_closing(order, closing_entry)
        EventBus.publish(:position_updated, build_position_event(order))
      rescue StandardError => e
        HotPathErrorPolicy.log_swallowed_error(
          component: "OrderHandler",
          operation: "process_fill",
          error:     e,
          exchange_order_id: @event.exchange_order_id
        )
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

      def create_trade_if_closing(order, entry_position)
        return if entry_position.nil?
        return if entry_position.id.present? && Trade.exists?(position_id: entry_position.id)

        pnl = calculate_pnl(entry_position, order)
        Trade.create!(
          portfolio_id:     order.portfolio_id,
          position_id:      entry_position.id,
          symbol:           order.symbol,
          side:             entry_position.side,
          size:             order.filled_qty,
          entry_price:      entry_position.entry_price,
          exit_price:       order.avg_fill_price,
          pnl_usd:          pnl,
          pnl_inr:          pnl * Finance::UsdInrRate.current,
          duration_seconds: (Time.current - entry_position.entry_time.to_time).to_i,
          closed_at:        Time.current,
          strategy:         ENV.fetch("BOT_TRADE_STRATEGY", "multi_timeframe"),
          regime:           ENV.fetch("BOT_TRADE_REGIME", "unknown")
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def calculate_pnl(position, order)
        multiplier = position.side == "long" ? 1 : -1
        (order.avg_fill_price - position.entry_price) * order.filled_qty * multiplier
      end

      def build_position_event(order)
        pos = Position.find_by(symbol: order.symbol, portfolio_id: order.portfolio_id)
        Events::PositionUpdated.new(
          symbol:         order.symbol,
          side:           pos&.side || "unknown",
          size:           order.filled_qty,
          entry_price:    pos&.entry_price || 0,
          mark_price:     MarkPrice.for_symbol(order.symbol)&.to_f || 0.0,
          unrealized_pnl: 0.0,
          status:         pos&.status || "closed"
        )
      end
    end
  end
end
