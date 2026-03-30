# frozen_string_literal: true

module Trading
  module Handlers
    class PositionHandler
      def initialize(event)
        @event = event
      end

      def call
        ActionCable.server.broadcast("trading_channel", {
          type:    "position_updated",
          symbol:  @event.symbol,
          side:    @event.side,
          size:    @event.size,
          status:  @event.status,
          pnl:     @event.unrealized_pnl
        })
      rescue => e
        Rails.logger.error("[PositionHandler] Broadcast failed for #{@event.symbol}: #{e.message}")
      end
    end
  end
end
