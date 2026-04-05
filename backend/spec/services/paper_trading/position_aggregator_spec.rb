# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::PositionAggregator do
  let(:wallet) { create(:paper_wallet, seed_inr: BigDecimal("50000")) }
  let(:product) do
    create(:paper_product_snapshot,
      symbol: "SOLUSD",
      contract_value: BigDecimal("1"),
      risk_unit_per_contract: BigDecimal("1"),
      default_leverage: 10)
  end
  let(:signal) { create(:paper_trading_signal, paper_wallet: wallet, product_id: product.product_id) }

  it "derives open side, contracts, avg entry, and used margin from fills" do
    buy_order = create(:paper_order,
      paper_wallet: wallet,
      paper_product_snapshot: product,
      paper_trading_signal: signal,
      side: "buy",
      size: 5,
      state: "filled")

    entry_fill = buy_order.paper_fills.create!(
      size: 5,
      filled_qty: 5,
      closed_qty: 2,
      margin_inr_per_fill: BigDecimal("3357.50"),
      liquidity: "taker",
      price: BigDecimal("79"),
      filled_at: Time.current
    )

    snapshot = described_class.call([ entry_fill ])

    expect(snapshot.symbol).to eq("SOLUSD")
    expect(snapshot.side).to eq("buy")
    expect(snapshot.contracts).to eq(3)
    expect(snapshot.avg_entry_price).to eq(BigDecimal("79"))
    expect(snapshot.contract_value).to eq(BigDecimal("1"))
    expect(snapshot.used_margin_inr).to eq(BigDecimal("2014.50"))
  end
end
