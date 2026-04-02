# frozen_string_literal: true

module PaperTrading
  class ProcessSignalJob < ApplicationJob
    queue_as :trading

    def perform(signal_id)
      signal = PaperTradingSignal.lock.find(signal_id)
      return unless signal.pending?
      return if PaperOrder.exists?(paper_trading_signal_id: signal.id)

      wallet = PaperWallet.lock.find(signal.paper_wallet_id)
      product = PaperProductSnapshot.find_by!(product_id: signal.product_id)

      ltp = PaperTrading::RedisStore.get_ltp(product.product_id) || product.live_price
      unless ltp&.to_d&.positive?
        signal.update!(status: "rejected", rejection_reason: "no live price for product")
        return
      end
      ltp = ltp.to_d

      allocator = PaperTrading::CapitalAllocator.new(
        equity: wallet.equity,
        risk_pct: signal.risk_pct,
        target_profit_pct: BigDecimal("0.1"),
        risk_unit_value: product.risk_unit_per_contract
      )
      allocation = allocator.call(
        side: signal.side,
        entry_price: signal.entry_price,
        stop_price: signal.stop_price
      )

      unless allocation.valid?
        signal.update!(status: "rejected", rejection_reason: "quantity below 1 after allocation")
        return
      end

      qty = allocation.quantity.to_i

      ActiveRecord::Base.transaction do
        order = PaperOrder.create!(
          paper_wallet: wallet,
          paper_product_snapshot: product,
          paper_trading_signal: signal,
          side: normalize_order_side(signal.side),
          order_type: "market_order",
          size: qty,
          state: "filled",
          client_order_id: "paper-signal-#{signal.id}",
          avg_fill_price: ltp
        )

        FillApplicator.new(order: order, wallet: wallet, product: product).call(price: ltp, size: qty)
        signal.update!(status: "filled")
      end

      RepriceWalletJob.perform_later(wallet.id)
    end

    private

    def normalize_order_side(side)
      case side.to_s.downcase
      when "long" then "buy"
      when "short" then "sell"
      else
        side.to_s.downcase
      end
    end
  end
end
