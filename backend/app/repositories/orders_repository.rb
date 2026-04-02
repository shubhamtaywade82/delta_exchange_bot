# frozen_string_literal: true

module OrdersRepository
  def self.create!(attrs)
    Order.create!(attrs)
  end

  def self.find_by_exchange_id(exchange_order_id)
    Order.find_by(exchange_order_id: exchange_order_id)
  end

  def self.update_from_fill(exchange_order_id:, filled_qty:, avg_fill_price:, status:)
    exchange_fill_id = [exchange_order_id, filled_qty, avg_fill_price, status].join(":")

    Trading::FillProcessor.process(
      Trading::Events::OrderFilled.new(
        exchange_fill_id: exchange_fill_id,
        exchange_order_id: exchange_order_id,
        quantity: filled_qty,
        price: avg_fill_price,
        status: status,
        filled_at: Time.current,
        raw_payload: { source: "repository_update" }
      )
    )
  end

  def self.close_position(position_id:, reason:, mark_price:)
    position = Position.find(position_id)
    target_status = liquidation_reason?(reason) ? "liquidated" : "closed"
    trade = nil

    Position.transaction do
      position.update!(
        status: target_status,
        exit_price: mark_price,
        exit_time: Time.current,
        pnl_usd: position.pnl_usd.to_d,
        pnl_inr: position.pnl_inr.to_d
      )

      trade = Trading::Learning::CreditAssigner.finalize_trade!(
        position,
        entry_features: position.entry_features || {},
        strategy: position.strategy.presence || "scalping",
        regime: position.regime.presence || "mean_reversion"
      )
      Trading::Learning::OnlineUpdater.update!(trade)
      Trading::Learning::Metrics.update(trade)
      Trading::Learning::AiRefinementTrigger.call(reason: "trade_closed:#{position.id}")

      Rails.logger.warn("[OrdersRepository] Forced close position=#{position.id} reason=#{reason} mark=#{mark_price}")
    end

    notify_trade_closed_telegram(trade, reason)
    position
  end

  def self.notify_trade_closed_telegram(trade, reason)
    return unless trade

    Trading::TelegramNotifications.deliver do |n|
      n.notify_trade_closed(
        symbol: trade.symbol,
        exit_price: trade.exit_price.to_f,
        pnl_usd: trade.pnl_usd.to_f,
        pnl_inr: trade.pnl_inr.to_f,
        duration_seconds: trade.duration_seconds.to_i,
        reason: reason.to_s
      )
    end
  end
  private_class_method :notify_trade_closed_telegram

  def self.liquidation_reason?(reason)
    reason.to_s == "LIQUIDATION_EXIT"
  end
end
