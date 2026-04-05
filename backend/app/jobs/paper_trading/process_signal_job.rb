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

      quantity = compute_fill_quantity(signal, wallet, product)
      return unless quantity

      reject_unaffordable_fill!(signal, wallet, product, quantity, ltp) && return

      execute_matching_pipeline(signal:, wallet:, product:, quantity:, ltp:)
    end

    def resolve_live_price(signal, product)
      ltp = PaperTrading::RedisStore.get_ltp(product.product_id) || product.live_price
      unless ltp&.to_d&.positive?
        signal.update!(status: "rejected", rejection_reason: "no live price for product")
        return nil
      end

      ltp.to_d
    end

    def compute_fill_quantity(signal, wallet, product)
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

    def reject_unaffordable_fill!(signal, wallet, product, quantity, ltp)
      leverage = effective_leverage(product)
      required_margin_inr = PositionManager.estimate_margin_inr(
        quantity: quantity,
        price: ltp,
        contract_value: product.contract_value,
        leverage: leverage,
        usd_inr_rate: Finance::UsdInrRate.current
      )
      return false if required_margin_inr <= wallet.available_inr.to_d

      signal.update!(status: "rejected", rejection_reason: "insufficient available margin for fill price")
      true
    end

    def execute_matching_pipeline(signal:, wallet:, product:, quantity:, ltp:)
      fill_error_message = nil
      order = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        order = create_market_order(signal:, wallet:, product:, quantity:, ltp:)
        fills = matching_engine_for(ltp:).execute(order)
        apply_fills!(fills:, order:, wallet:, product:)
        signal.update!(status: "filled")
      rescue PaperTrading::PositionManager::InsufficientMarginError => e
        fill_error_message = e.message
        raise ActiveRecord::Rollback
      end

      return finalize_rejected_signal(signal, fill_error_message) if fill_error_message.present?

      if order&.paper_fills&.exists?
        RepriceWalletJob.perform_later(wallet.id)
      else
        signal.update!(status: "rejected", rejection_reason: "insufficient order book liquidity")
      end
    end

    def create_market_order(signal:, wallet:, product:, quantity:, ltp:)
      PaperOrder.create!(
        paper_wallet: wallet,
        paper_product_snapshot: product,
        paper_trading_signal: signal,
        side: normalize_order_side(signal.side),
        order_type: "market_order",
        size: quantity,
        state: "filled",
        client_order_id: "paper-signal-#{signal.id}",
        avg_fill_price: ltp
      )
    end

    def matching_engine_for(ltp:)
      order_book = OrderBook.new
      order_book.update!(build_order_book_snapshot(ltp:))
      MatchingEngine.new(order_book: order_book)
    end

    def build_order_book_snapshot(ltp:)
      depth = market_depth
      spread_multiplier = spread_bps / 10_000.to_d / 2.to_d
      ask = ltp * (1 + spread_multiplier)
      bid = ltp * (1 - spread_multiplier)

      {
        bids: [ [ bid, depth ] ],
        asks: [ [ ask, depth ] ]
      }
    end

    def apply_fills!(fills:, order:, wallet:, product:)
      depth = market_depth

      fills.each do |fill|
        impacted_price = ImpactModel.apply(
          price: fill[:price],
          quantity: fill[:qty],
          depth: depth,
          side: order.side
        )

        FillApplier.new(order: order, wallet: wallet, product: product).call(
          price: impacted_price,
          size: fill[:qty],
          leverage: effective_leverage(product),
          liquidity: fill[:liquidity],
          market_snapshot: { bid: impacted_price, ask: impacted_price, depth: depth }
        )
      end
    end

    def spread_bps
      ENV.fetch("PAPER_SPREAD_BPS", "0").to_d
    end

    def market_depth
      ENV.fetch("PAPER_MARKET_DEPTH", "100").to_d
    end

    def finalize_rejected_signal(signal, message)
      signal.update!(status: "rejected", rejection_reason: message)
    end

    def effective_leverage(product)
      [ product.default_leverage.to_i, 1 ].max
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
