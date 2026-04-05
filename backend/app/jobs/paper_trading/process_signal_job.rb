# frozen_string_literal: true

module PaperTrading
  class ProcessSignalJob < ApplicationJob
    queue_as :trading

    def perform(signal_id)
      signal = PaperTradingSignal.find(signal_id)
      signal.with_lock do
        return unless signal.pending?
        return if PaperOrder.exists?(paper_trading_signal_id: signal.id)

        process_locked_signal(signal)
      end
    end

    private

    def process_locked_signal(signal)
      wallet = PaperWallet.find(signal.paper_wallet_id)
      product = PaperProductSnapshot.find_by!(product_id: signal.product_id)
      wallet.reload
      wallet.recompute_from_ledger!

      ltp = resolve_live_price(signal, product)
      return unless ltp

      qty = compute_fill_quantity(signal, wallet, product, ltp)
      return unless qty

      reject_unaffordable_fill!(signal, wallet, product, qty, ltp) && return

      execute_fill(signal, wallet, product, qty, ltp)
    end

    def resolve_live_price(signal, product)
      ltp = PaperTrading::RedisStore.get_ltp(product.product_id) || product.live_price
      unless ltp&.to_d&.positive?
        signal.update!(status: "rejected", rejection_reason: "no live price for product")
        return nil
      end
      ltp.to_d
    end

    def compute_fill_quantity(signal, wallet, product, _ltp)
      leverage = effective_leverage(product)
      result = PaperTrading::RrPositionSizer.compute!(
        max_loss_inr: signal.max_loss_inr,
        available_margin_inr: wallet.available_inr.to_d,
        usd_inr_rate: Finance::UsdInrRate.current,
        entry_price: signal.entry_price.to_f,
        stop_price: signal.stop_price.to_f,
        contract_value: product.contract_value.to_f,
        leverage: leverage,
        position_size_limit: product.position_size_limit
      )

      return result.final_contracts if result.final_contracts >= 1

      signal.update!(status: "rejected", rejection_reason: "quantity below 1 after allocation")
      nil
    end

    def reject_unaffordable_fill!(signal, wallet, product, qty, ltp)
      leverage = effective_leverage(product)
      required_margin_inr = PositionManager.estimate_margin_inr(
        quantity: qty,
        price: ltp,
        contract_value: product.contract_value,
        leverage: leverage,
        usd_inr_rate: Finance::UsdInrRate.current
      )
      return false if required_margin_inr <= wallet.available_inr.to_d

      signal.update!(status: "rejected", rejection_reason: "insufficient available margin for fill price")
      true
    end

    def execute_fill(signal, wallet, product, qty, ltp)
      leverage = effective_leverage(product)
      fill_error_message = nil

      ActiveRecord::Base.transaction(requires_new: true) do
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

        FillApplicator.new(order: order, wallet: wallet, product: product).call(
          price: ltp,
          size: qty,
          leverage: leverage
        )
        signal.update!(status: "filled")
      rescue PaperTrading::PositionManager::InsufficientMarginError => e
        fill_error_message = e.message
        raise ActiveRecord::Rollback
      end

      if fill_error_message.present?
        signal.update!(status: "rejected", rejection_reason: fill_error_message)
        return
      end

      RepriceWalletJob.perform_later(wallet.id) if signal.reload.filled?
    end

    def effective_leverage(product)
      [product.default_leverage.to_i, 1].max
    end

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
