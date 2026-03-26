# frozen_string_literal: true

module Trading
  class KillSwitch
    def self.call(session_id, client:)
      new(session_id, client).trigger!
    end

    def self.force_exit_position(position, client)
      close_side = position.side == "long" ? "sell" : "buy"
      client.place_order(
        product_id: position.product_id,
        side:       close_side,
        order_type: "market_order",
        size:       position.size
      )
      position.update!(status: "closed", exit_time: Time.current)
    rescue => e
      Rails.logger.error("[KillSwitch] force_exit_position failed for #{position.symbol}: #{e.message}")
    end

    def initialize(session_id, client)
      @session_id = session_id
      @client     = client
    end

    def trigger!
      Rails.logger.warn("[KillSwitch] TRIGGERED for session #{@session_id}")
      cancel_open_orders!
      close_open_positions!
      mark_session_stopped!
    end

    private

    def cancel_open_orders!
      Order.where(trading_session_id: @session_id, status: %w[pending open]).each do |order|
        @client.cancel_order(order.exchange_order_id)
        order.update!(status: "cancelled")
      rescue => e
        Rails.logger.error("[KillSwitch] cancel_order failed for order #{order.id}: #{e.message}")
      end
    end

    def close_open_positions!
      Position.where(status: "open").each do |position|
        self.class.force_exit_position(position, @client)
      end
    end

    def mark_session_stopped!
      TradingSession.find(@session_id).update!(status: "stopped", stopped_at: Time.current)
    end
  end
end
