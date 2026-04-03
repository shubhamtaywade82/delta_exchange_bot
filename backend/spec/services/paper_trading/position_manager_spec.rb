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
end
