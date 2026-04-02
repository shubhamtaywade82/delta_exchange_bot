# frozen_string_literal: true

module OrdersRepository
  TERMINAL_POSITION_STATUSES = %w[closed liquidated].freeze

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
    target_status = liquidation_reason?(reason) ? "liquidated" : "closed"
    trade = nil

    position = Position.transaction do
      pos = Position.lock.find(position_id)
      if TERMINAL_POSITION_STATUSES.include?(pos.status)
        Rails.logger.info(
          "[OrdersRepository] close_position skipped: position=#{position_id} already #{pos.status}"
        )
        next pos
      end

      realized_usd = realized_pnl_usd_at_mark(pos, mark_price)
      rate = Finance::UsdInrRate.current.to_d
      pos.update!(
        status: target_status,
        exit_price: mark_price,
        exit_time: Time.current,
        pnl_usd: realized_usd,
        pnl_inr: realized_usd * rate
      )

      trade = Trading::Learning::CreditAssigner.finalize_trade!(
        pos,
        entry_features: pos.entry_features || {},
        strategy: pos.strategy.presence || "scalping",
        regime: pos.regime.presence || "mean_reversion"
      )
      Trading::Learning::OnlineUpdater.update!(trade)
      Trading::Learning::Metrics.update(trade)
      Trading::Learning::AiRefinementTrigger.call(reason: "trade_closed:#{pos.id}")

      Rails.logger.warn("[OrdersRepository] Forced close position=#{pos.id} reason=#{reason} mark=#{mark_price}")
      pos
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

  # Mark-to-exit matches +Trading::Risk::PositionRisk+ (contract lot multiplier, long/short sign).
  def self.realized_pnl_usd_at_mark(position, mark_price)
    mark = mark_price.to_d
    return 0.to_d unless mark.positive?

    Trading::Risk::PositionRisk.call(position: position, mark_price: mark).unrealized_pnl.to_d
  end
  private_class_method :realized_pnl_usd_at_mark
end
