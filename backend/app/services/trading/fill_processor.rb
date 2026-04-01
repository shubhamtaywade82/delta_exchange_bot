# frozen_string_literal: true

module Trading
  # FillProcessor persists exchange fills idempotently and derives order/position state deterministically.
  class FillProcessor
    class OverfillError < StandardError; end

    def self.process(fill_event)
      new(fill_event).process
    end

    def initialize(fill_event)
      @fill_event = fill_event
    end

    # Applies one fill event atomically.
    # @return [Order, nil]
    def process
      order = find_order
      return nil unless order
      return order if @fill_event.exchange_fill_id.blank?

      applied_fill = false
      ActiveRecord::Base.transaction(isolation: :repeatable_read) do
        order.lock!

        guard_overfill!(order)
        fill = persist_fill!(order)
        return order unless fill

        mark_position_dirty(order.position_id)
        apply_order_aggregation!(order)
        position = PositionRecalculator.call(order.position_id) if order.position_id.present?
        apply_entry_context!(position) if position
        evaluate_risk!(position) if position
        applied_fill = true
      end

      publish_paper_wallet_after_fill if applied_fill

      order
    end

    private

    def find_order
      Order.find_by(exchange_order_id: @fill_event.exchange_order_id) ||
        Order.find_by(client_order_id: @fill_event.client_order_id)
    end

    def persist_fill!(order)
      return nil if Fill.exists?(exchange_fill_id: @fill_event.exchange_fill_id)

      order.fills.create!(
        exchange_fill_id: @fill_event.exchange_fill_id,
        quantity: @fill_event.quantity,
        price: @fill_event.price,
        fee: @fill_event.fee,
        filled_at: @fill_event.filled_at || Time.current,
        raw_payload: @fill_event.raw_payload
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def apply_order_aggregation!(order)
      totals = Fill.where(order_id: order.id)
                   .select("SUM(quantity) AS total_qty", "SUM(quantity * price) AS total_value", "SUM(fee) AS total_fee")
                   .take

      total_qty = totals.total_qty.to_d
      total_value = totals.total_value.to_d
      avg_fill_price = total_qty.zero? ? nil : (total_value / total_qty)

      order.apply_fill!(
        cumulative_qty: total_qty,
        avg_fill_price: avg_fill_price,
        exchange_status: @fill_event.status
      )
    end

    def guard_overfill!(order)
      existing_qty = Fill.where(order_id: order.id).sum(:quantity).to_d
      incoming_qty = BigDecimal(@fill_event.quantity.to_s)
      return unless existing_qty + incoming_qty > order.size.to_d

      raise OverfillError, "Overfill detected for order #{order.id}"
    end



    def apply_entry_context!(position)
      raw = Rails.cache.read("adaptive:entry_context:#{position.symbol}") || {}
      context = raw.respond_to?(:deep_stringify_keys) ? raw.deep_stringify_keys : raw
      position.update!(
        strategy: context["strategy"].presence || position.strategy,
        regime: context["regime"]&.to_s.presence || position.regime,
        entry_features: context["features"].presence || position.entry_features
      )
    end

    def evaluate_risk!(position)
      mark_price = Rails.cache.read("ltp:#{position.symbol}")&.to_d || position.entry_price.to_d
      portfolio = Trading::Risk::PortfolioSnapshot.current
      result = Trading::Risk::Engine.evaluate(position: position, mark_price: mark_price, portfolio: portfolio)
      Trading::Risk::Executor.handle!(position: position, signal: result[:liquidation], mark_price: mark_price)
    end

    def mark_position_dirty(position_id)
      return if position_id.blank?

      Position.where(id: position_id).update_all(needs_reconciliation: true)
    end

    def publish_paper_wallet_after_fill
      return unless PaperTrading.enabled?

      PaperWalletPublisher.publish!
    rescue StandardError => e
      Rails.logger.warn("[FillProcessor] PaperWalletPublisher failed: #{e.message}")
    end
  end
end
