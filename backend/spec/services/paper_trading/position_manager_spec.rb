# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::PositionManager do
  before { allow(Finance::UsdInrRate).to receive(:current).and_return(85) }

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
    side_order.paper_fills.create!(size: qty, price: px, filled_at: Time.current)
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
end
