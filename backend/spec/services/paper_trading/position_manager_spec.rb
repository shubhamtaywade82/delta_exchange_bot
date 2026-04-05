# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::PositionManager do
  before { allow(Finance::UsdInrRate).to receive(:current).and_return(85) }
  after { Rails.cache.clear }

  let(:wallet) { create(:paper_wallet) }
  let(:product) do
    create(:paper_product_snapshot, contract_value: "0.001", risk_unit_per_contract: "0.001", default_leverage: 1)
  end
  let(:signal) { create(:paper_trading_signal, paper_wallet: wallet, product_id: product.product_id) }
  let(:order) do
    create(:paper_order,
      paper_wallet: wallet,
      paper_product_snapshot: product,
      paper_trading_signal: signal,
      side: "buy",
      size: 10)
  end

  def fill_for(side_order, qty, px)
    side_order.paper_fills.create!(
      size: qty,
      filled_qty: qty,
      closed_qty: 0,
      margin_inr_per_fill: 0,
      liquidity: "taker",
      price: px,
      filled_at: Time.current
    )
  end

  describe "opening" do
    it "creates position and margin ledger" do
      fill = fill_for(order, 10, "50000")
      described_class.new(wallet: wallet, product: product).apply_fill(
        fill: fill,
        fill_side: "buy",
        quantity: 10,
        price: BigDecimal("50000")
      )
      pos = PaperPosition.find_by!(paper_wallet: wallet, paper_product_snapshot: product)
      expect(pos.net_quantity).to eq(10)
      expect(pos.side).to eq("buy")
      expect(PaperWalletLedgerEntry.where(entry_type: "margin_reserved").count).to eq(1)
      expect(PaperWalletLedgerEntry.where(entry_type: "commission").count).to eq(1)
    end
  end

  describe "adding same side" do
    before do
      f = fill_for(order, 10, "50000")
      described_class.new(wallet: wallet, product: product).apply_fill(
        fill: f, fill_side: "buy", quantity: 10, price: BigDecimal("50000")
      )
    end

    it "recomputes average entry" do
      order2 = create(:paper_order, paper_wallet: wallet, paper_product_snapshot: product, paper_trading_signal: signal, side: "buy", size: 10)
      fill = fill_for(order2, 10, "51000")
      described_class.new(wallet: wallet, product: product).apply_fill(
        fill: fill, fill_side: "buy", quantity: 10, price: BigDecimal("51000")
      )
      pos = PaperPosition.find_by!(paper_wallet: wallet, paper_product_snapshot: product)
      expect(pos.net_quantity).to eq(20)
      expect(pos.avg_entry_price).to eq(BigDecimal("50500"))
    end
  end

  describe "full close" do
    before do
      f = fill_for(order, 10, "50000")
      described_class.new(wallet: wallet, product: product).apply_fill(
        fill: f, fill_side: "buy", quantity: 10, price: BigDecimal("50000")
      )
    end

    it "removes position and records realized pnl" do
      sell_order = create(:paper_order, paper_wallet: wallet, paper_product_snapshot: product, paper_trading_signal: signal, side: "sell", size: 10)
      fill = fill_for(sell_order, 10, "55000")
      described_class.new(wallet: wallet, product: product).apply_fill(
        fill: fill, fill_side: "sell", quantity: 10, price: BigDecimal("55000")
      )
      expect(PaperPosition.find_by(paper_wallet: wallet, paper_product_snapshot: product)).to be_nil
      expect(wallet.reload.realized_pnl_inr).to eq(BigDecimal("4250"))
    end
  end

  describe "idempotent fill" do
    it "second apply with same fill is noop" do
      fill = fill_for(order, 10, "50000")
      mgr = described_class.new(wallet: wallet, product: product)
      mgr.apply_fill(fill: fill, fill_side: "buy", quantity: 10, price: BigDecimal("50000"))
      r = mgr.apply_fill(fill: fill, fill_side: "buy", quantity: 10, price: BigDecimal("50000"))
      expect(r.action).to eq(:noop)
      expect(PaperPosition.count).to eq(1)
    end

    it "does not duplicate ledger rows for same fill reference" do
      fill = fill_for(order, 2, "50000")
      manager = described_class.new(wallet: wallet, product: product)

      manager.apply_fill(fill: fill, fill_side: "buy", quantity: 2, price: BigDecimal("50000"))
      manager.apply_fill(fill: fill, fill_side: "buy", quantity: 2, price: BigDecimal("50000"))

      refs = PaperWalletLedgerEntry.where(paper_wallet: wallet, external_ref: "PaperFill:#{fill.id}")
      expect(refs.where(entry_type: "margin_reserved").count).to eq(1)
      expect(refs.where(entry_type: "commission", sub_type: "entry_fee").count).to eq(1)
    end
  end

  describe "margin validation" do
    it "rejects opening when required margin exceeds available balance" do
      small_wallet = create(:paper_wallet, seed_inr: BigDecimal("100"))
      tiny_signal = create(:paper_trading_signal, paper_wallet: small_wallet, product_id: product.product_id)
      tiny_order = create(:paper_order,
        paper_wallet: small_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: tiny_signal,
        side: "buy",
        size: 1)
      fill = fill_for(tiny_order, 1, "50000")

      expect do
        described_class.new(wallet: small_wallet, product: product).apply_fill(
          fill: fill,
          fill_side: "buy",
          quantity: 1,
          price: BigDecimal("50000"),
          leverage: 1
        )
      end.to raise_error(PaperTrading::PositionManager::InsufficientMarginError)

      expect(PaperPosition.where(paper_wallet: small_wallet).count).to eq(0)
      expect(PaperWalletLedgerEntry.where(paper_wallet: small_wallet, entry_type: "margin_reserved").count).to eq(0)
    end

    it "keeps close committed when flip excess cannot be afforded" do
      medium_wallet = create(:paper_wallet, seed_inr: BigDecimal("10000"))
      medium_signal = create(:paper_trading_signal, paper_wallet: medium_wallet, product_id: product.product_id)
      buy_order = create(:paper_order,
        paper_wallet: medium_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: medium_signal,
        side: "buy",
        size: 1)
      buy_fill = fill_for(buy_order, 1, "50000")
      manager = described_class.new(wallet: medium_wallet, product: product)
      manager.apply_fill(
        fill: buy_fill,
        fill_side: "buy",
        quantity: 1,
        price: BigDecimal("50000"),
        leverage: 1
      )

      sell_order = create(:paper_order,
        paper_wallet: medium_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: medium_signal,
        side: "sell",
        size: 5)
      sell_fill = fill_for(sell_order, 5, "50000")
      result = manager.apply_fill(
        fill: sell_fill,
        fill_side: "sell",
        quantity: 5,
        price: BigDecimal("50000"),
        leverage: 1
      )

      expect(result.action).to eq(:closed)
      expect(PaperPosition.where(paper_wallet: medium_wallet, paper_product_snapshot: product).count).to eq(0)
      expect(medium_wallet.reload.used_margin_inr).to eq(0)
    end

    it "keeps close committed when flip position create fails" do
      medium_wallet = create(:paper_wallet, seed_inr: BigDecimal("10000"))
      medium_signal = create(:paper_trading_signal, paper_wallet: medium_wallet, product_id: product.product_id)
      buy_order = create(:paper_order,
        paper_wallet: medium_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: medium_signal,
        side: "buy",
        size: 1)
      buy_fill = fill_for(buy_order, 1, "50000")
      manager = described_class.new(wallet: medium_wallet, product: product)
      manager.apply_fill(
        fill: buy_fill,
        fill_side: "buy",
        quantity: 1,
        price: BigDecimal("50000"),
        leverage: 1
      )

      allow(PaperPosition).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(PaperPosition.new))

      sell_order = create(:paper_order,
        paper_wallet: medium_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: medium_signal,
        side: "sell",
        size: 2)
      sell_fill = fill_for(sell_order, 2, "50000")
      result = manager.apply_fill(
        fill: sell_fill,
        fill_side: "sell",
        quantity: 2,
        price: BigDecimal("50000"),
        leverage: 1
      )

      expect(result.action).to eq(:closed)
      expect(PaperPosition.where(paper_wallet: medium_wallet, paper_product_snapshot: product).count).to eq(0)
      expect(medium_wallet.reload.used_margin_inr).to eq(0)
    end
  end

  describe "partial exit accounting with per-fill margins" do
    let(:wallet) { create(:paper_wallet, seed_inr: BigDecimal("50000")) }
    let(:product) do
      create(:paper_product_snapshot,
        symbol: "SOLUSD",
        contract_value: "1",
        risk_unit_per_contract: "1",
        default_leverage: 10,
        raw_metadata: { "taker_fee_rate" => "0.0005" })
    end

    it "releases FIFO margin for partial exits" do
      manager = described_class.new(wallet: wallet, product: product)
      first_buy = fill_for(order, 3, "80")
      manager.apply_fill(fill: first_buy, fill_side: "buy", quantity: 3, price: BigDecimal("80"), leverage: 10)

      second_order = create(:paper_order, paper_wallet: wallet, paper_product_snapshot: product, paper_trading_signal: signal, side: "buy", size: 2)
      second_buy = fill_for(second_order, 2, "77.5")
      manager.apply_fill(fill: second_buy, fill_side: "buy", quantity: 2, price: BigDecimal("77.5"), leverage: 10)

      close_order = create(:paper_order, paper_wallet: wallet, paper_product_snapshot: product, paper_trading_signal: signal, side: "sell", size: 2)
      close_fill = fill_for(close_order, 2, "82")
      manager.apply_fill(fill: close_fill, fill_side: "sell", quantity: 2, price: BigDecimal("82"), leverage: 10)

      first_buy.reload
      second_buy.reload
      wallet.reload

      expect(first_buy.closed_qty).to eq(2)
      expect(second_buy.closed_qty).to eq(0)
      expect(wallet.used_margin_inr).to eq(BigDecimal("1997.50"))
    end

    it "matches net pnl after GST-inclusive taker fees through full close" do
      manager = described_class.new(wallet: wallet, product: product)
      manager.apply_fill(fill: fill_for(order, 3, "80"), fill_side: "buy", quantity: 3, price: BigDecimal("80"), leverage: 10)

      second_order = create(:paper_order, paper_wallet: wallet, paper_product_snapshot: product, paper_trading_signal: signal, side: "buy", size: 2)
      manager.apply_fill(fill: fill_for(second_order, 2, "77.5"), fill_side: "buy", quantity: 2, price: BigDecimal("77.5"), leverage: 10)

      partial_sell = create(:paper_order, paper_wallet: wallet, paper_product_snapshot: product, paper_trading_signal: signal, side: "sell", size: 2)
      manager.apply_fill(fill: fill_for(partial_sell, 2, "82"), fill_side: "sell", quantity: 2, price: BigDecimal("82"), leverage: 10)

      final_sell = create(:paper_order, paper_wallet: wallet, paper_product_snapshot: product, paper_trading_signal: signal, side: "sell", size: 3)
      manager.apply_fill(fill: fill_for(final_sell, 3, "84"), fill_side: "sell", quantity: 3, price: BigDecimal("84"), leverage: 10)

      wallet.reload
      total_fees = wallet.paper_wallet_ledger_entries.where(entry_type: "commission").sum(:amount_inr)

      expect(wallet.balance_inr).to eq(BigDecimal("51744.33"))
      expect(wallet.used_margin_inr).to eq(0)
      expect(total_fees).to eq(BigDecimal("40.67"))
    end
  end

  describe "maintenance margin liquidation" do
    # Test env uses :null_store, so Rails.cache.write is a no-op. Liquidation reads mark prices from cache.
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    let(:wallet) { create(:paper_wallet, seed_inr: BigDecimal("500")) }
    let(:product) do
      create(:paper_product_snapshot,
        symbol: "SOLUSD",
        contract_value: "1",
        risk_unit_per_contract: "1",
        default_leverage: 10,
        raw_metadata: { "maintenance_margin" => "2.0" })
    end

    before do
      allow(Rails).to receive(:cache).and_return(memory_cache)
    end

    around do |example|
      previous_cap = ENV["PAPER_MAX_LEVERAGE_CAP"]
      ENV["PAPER_MAX_LEVERAGE_CAP"] = "10000"
      example.run
    ensure
      if previous_cap
        ENV["PAPER_MAX_LEVERAGE_CAP"] = previous_cap
      else
        ENV.delete("PAPER_MAX_LEVERAGE_CAP")
      end
    end

    it "forces liquidation when equity drops below maintenance margin requirement" do
      Rails.cache.write("mark_price:#{product.symbol}", [ BigDecimal("4"), Time.current ])
      manager = described_class.new(wallet: wallet, product: product)
      manager.apply_fill(fill: fill_for(order, 1, "4"), fill_side: "buy", quantity: 1, price: BigDecimal("4"))

      expect(PaperPosition.where(paper_wallet: wallet, paper_product_snapshot: product)).to be_empty
      expect(wallet.reload.used_margin_inr).to eq(0)
    end

    it "uses Rails.cache mark for liquidation maintenance, not the product's far-off catalog mark_price" do
      Rails.cache.write("mark_price:SOLUSD-MARK", [ BigDecimal("100"), Time.current ])
      mark_product = create(:paper_product_snapshot,
        symbol: "SOLUSD-MARK",
        contract_value: "1",
        risk_unit_per_contract: "1",
        default_leverage: 100,
        raw_metadata: { "maintenance_margin" => "0.01" },
        mark_price: BigDecimal("999"),
        close_price: BigDecimal("999"))
      mark_signal = create(:paper_trading_signal, paper_wallet: wallet, product_id: mark_product.product_id)
      buy_order = create(:paper_order,
        paper_wallet: wallet,
        paper_product_snapshot: mark_product,
        paper_trading_signal: mark_signal,
        side: "buy",
        size: 1)
      fill = fill_for(buy_order, 1, "100")

      manager = described_class.new(wallet: wallet, product: mark_product)
      manager.apply_fill(fill: fill, fill_side: "buy", quantity: 1, price: BigDecimal("100"), leverage: 100)

      expect(PaperPosition.where(paper_wallet: wallet, paper_product_snapshot: mark_product).count).to eq(1)
    end

    it "skips liquidation when mark price is unavailable" do
      manager = described_class.new(wallet: wallet, product: product)
      manager.apply_fill(fill: fill_for(order, 1, "4"), fill_side: "buy", quantity: 1, price: BigDecimal("4"))

      expect(PaperPosition.where(paper_wallet: wallet, paper_product_snapshot: product).count).to eq(1)
    end

    it "liquidates only required contracts incrementally" do
      deep_wallet = create(:paper_wallet, seed_inr: BigDecimal("8000"))
      deep_signal = create(:paper_trading_signal, paper_wallet: deep_wallet, product_id: product.product_id)
      deep_order = create(:paper_order,
        paper_wallet: deep_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: deep_signal,
        side: "buy",
        size: 2)

      Rails.cache.write("mark_price:#{product.symbol}", [ BigDecimal("4"), Time.current ])
      product.update!(raw_metadata: { "maintenance_margin" => "12.0", "liquidation_step_size" => 1 })
      manager = described_class.new(wallet: deep_wallet, product: product)

      manager.apply_fill(fill: fill_for(deep_order, 2, "4"), fill_side: "buy", quantity: 2, price: BigDecimal("4"), leverage: 1)

      remaining = PaperPosition.find_by(paper_wallet: deep_wallet, paper_product_snapshot: product)
      expect(remaining).to be_present
      expect(remaining.net_quantity).to eq(1)
      liquidation_rows = deep_wallet.reload.paper_wallet_ledger_entries.where(sub_type: "liquidation_margin_release")
      expect(liquidation_rows.count).to eq(1)
    end

    it "skips liquidation on stale mark payload" do
      Rails.cache.write("mark_price:#{product.symbol}", [ BigDecimal("4"), 5.seconds.ago ])
      manager = described_class.new(wallet: wallet, product: product)

      manager.apply_fill(fill: fill_for(order, 1, "4"), fill_side: "buy", quantity: 1, price: BigDecimal("4"))

      expect(PaperPosition.where(paper_wallet: wallet, paper_product_snapshot: product).count).to eq(1)
    end

    it "never leaves wallet equity negative after forced liquidation" do
      high_loss_product = create(:paper_product_snapshot,
        symbol: "SOLUSD-BKR",
        contract_value: "1",
        risk_unit_per_contract: "1",
        default_leverage: 100,
        raw_metadata: { "maintenance_margin" => "1.0", "liquidation_fee_rate" => "0.003", "liquidation_step_size" => 10 })
      Rails.cache.write("mark_price:SOLUSD-BKR", [ BigDecimal("1"), Time.current ])
      signal = create(:paper_trading_signal, paper_wallet: wallet, product_id: high_loss_product.product_id)
      buy_order = create(:paper_order,
        paper_wallet: wallet,
        paper_product_snapshot: high_loss_product,
        paper_trading_signal: signal,
        side: "buy",
        size: 1)

      manager = described_class.new(wallet: wallet, product: high_loss_product)
      manager.apply_fill(fill: fill_for(buy_order, 1, "100"), fill_side: "buy", quantity: 1, price: BigDecimal("100"), leverage: 100)

      wallet.reload
      expect(wallet.equity_inr).to eq(0)
      expect(wallet.balance_inr).to eq(0)
      expect(wallet.status).to eq("bankrupt")
    end

    it "rejects new fills when wallet is bankrupt" do
      wallet.update!(status: "bankrupt")
      manager = described_class.new(wallet: wallet, product: product)

      expect do
        manager.apply_fill(fill: fill_for(order, 1, "4"), fill_side: "buy", quantity: 1, price: BigDecimal("4"))
      end.to raise_error(PaperTrading::PositionManager::InsufficientMarginError, /bankrupt/)
    end

    it "handles funding before liquidation without double counting" do
      deep_wallet = create(:paper_wallet, seed_inr: BigDecimal("8000"))
      deep_signal = create(:paper_trading_signal, paper_wallet: deep_wallet, product_id: product.product_id)
      deep_order = create(:paper_order,
        paper_wallet: deep_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: deep_signal,
        side: "buy",
        size: 2)

      product.update!(raw_metadata: { "maintenance_margin" => "12.0", "liquidation_step_size" => 1 })
      manager = described_class.new(wallet: deep_wallet, product: product)
      manager.apply_fill(fill: fill_for(deep_order, 2, "4"), fill_side: "buy", quantity: 2, price: BigDecimal("4"), leverage: 1)

      PaperTrading::FundingApplier.new(wallet: deep_wallet, usd_inr_rate: 85).call(
        funding_rate: BigDecimal("0.001"),
        mark_prices: { product.product_id => BigDecimal("4") }
      )

      add_order = create(:paper_order,
        paper_wallet: deep_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: deep_signal,
        side: "buy",
        size: 1)

      Rails.cache.write("mark_price:#{product.symbol}", [ BigDecimal("4"), Time.current ])
      manager.apply_fill(fill: fill_for(add_order, 1, "4"), fill_side: "buy", quantity: 1, price: BigDecimal("4"), leverage: 1)

      entries = deep_wallet.reload.paper_wallet_ledger_entries
      expect(entries.where(entry_type: "funding").count).to be >= 1
      expect(entries.where(sub_type: "liquidation_margin_release").count).to be >= 1
    end
  end

  describe "concurrency" do
    it "handles concurrent reprocessing of the same fill safely" do
      fill = fill_for(order, 1, "50000")
      manager = described_class.new(wallet: wallet, product: product)

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            manager.apply_fill(fill: fill, fill_side: "buy", quantity: 1, price: BigDecimal("50000"))
          end
        end
      end
      threads.each(&:join)

      refs = PaperWalletLedgerEntry.where(paper_wallet: wallet, external_ref: "PaperFill:#{fill.id}")
      expect(refs.where(entry_type: "margin_reserved").count).to eq(1)
      expect(refs.where(entry_type: "commission", sub_type: "entry_fee").count).to eq(1)
      expect(PaperPosition.where(paper_wallet: wallet, paper_product_snapshot: product).count).to eq(1)
    end
  end
end
