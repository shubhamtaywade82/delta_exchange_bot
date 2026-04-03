# frozen_string_literal: true

module Trading
  # Cancels session orders and closes positions on the exchange — operational emergency stop,
  # not portfolio PnL/exposure guardrails (see Trading::Risk::PortfolioGuard).
  class EmergencyShutdown
    def self.call(session_id, client:)
      new(session_id, client).trigger!
    end

    def self.force_exit_position(position, client, reason: "FORCE_EXIT")
      unless PaperTrading.enabled?
        close_side = position.side == "long" ? "sell" : "buy"
        client.place_order(
          product_id: position.product_id,
          side:       close_side,
          order_type: "market_order",
          size:       position.size
        )
      end

      OrdersRepository.close_position(
        position_id: position.id,
        reason: reason,
        mark_price: latest_mark_price_for(position)
      )
    rescue => e
      Rails.logger.error("[EmergencyShutdown] force_exit_position failed for #{position.symbol}: #{e.message}")
    end

    def initialize(session_id, client)
      @session_id = session_id
      @client     = client
    end

    def trigger!
      session = TradingSession.find(@session_id)
      Rails.logger.warn("[EmergencyShutdown] TRIGGERED for session #{@session_id}")
      cancel_open_orders!
      close_open_positions_for_portfolio!(session.portfolio_id)
      session.update!(status: "stopped", stopped_at: Time.current)
    end

    private

    def cancel_open_orders!
      Order.where(trading_session_id: @session_id).find_each do |order|
        next unless order.open?

        if order.exchange_order_id.present? && !PaperTrading.enabled?
          @client.cancel_order(order.exchange_order_id)
        end
        order.update!(status: "cancelled")
      rescue => e
        Rails.logger.error("[EmergencyShutdown] cancel_order failed for order #{order.id}: #{e.message}")
      end
    end

    def close_open_positions_for_portfolio!(portfolio_id)
      Position.active.where(portfolio_id: portfolio_id).find_each do |position|
        self.class.force_exit_position(position, @client, reason: "EMERGENCY_SHUTDOWN")
      end
    end

    def self.latest_mark_price_for(position)
      Rails.cache.read("ltp:#{position.symbol}")&.to_d || position.entry_price.to_d
    end
  end
end
