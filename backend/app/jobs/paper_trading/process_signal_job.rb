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

      rate = Finance::UsdInrRate.current
      # Wallet amounts are USD (Delta settlement); convert via rate for PositionSizer INR↔USD bridge.
      balance_inr = (wallet.equity.to_d * rate).to_f
      margin_wallet_usd = wallet.available_capital.to_d.to_f
      leverage = [ product.default_leverage.to_i, 1 ].max

      result = Finance::PositionSizer.compute!(
        balance_inr: balance_inr,
        risk_percent: signal.risk_pct.to_f,
        entry_price: signal.entry_price.to_f,
        stop_price: signal.stop_price.to_f,
        contract_value: product.contract_value.to_f,
        usd_inr: rate,
        leverage: leverage,
        margin_wallet_usd: margin_wallet_usd,
        position_size_limit: product.position_size_limit
      )

      unless result.final_contracts >= 1
        signal.update!(status: "rejected", rejection_reason: "quantity below 1 after allocation")
        return
      end

      qty = result.final_contracts

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

        FillApplicator.new(order: order, wallet: wallet, product: product).call(
          price: ltp,
          size: qty,
          leverage: leverage
        )
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
