# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::RepriceWalletJob do
  let(:wallet) { create(:paper_wallet, cash_balance: "0", realized_pnl: "0", unrealized_pnl: "0", equity: "0", reserved_margin: "0") }
  let(:product) { create(:paper_product_snapshot, product_id: 99, mark_price: "100", close_price: "100", risk_unit_per_contract: "1") }

  before do
    PaperPosition.create!(
      paper_wallet: wallet,
      paper_product_snapshot: product,
      side: "buy",
      net_quantity: 2,
      avg_entry_price: "90",
      risk_unit_per_contract: "1"
    )
  end

  it "rebuilds equity from DB prices when Redis LTP is empty" do
    allow(PaperTrading::RedisStore).to receive(:get_all_ltp_for_product_ids).and_return({})

    described_class.perform_now(wallet.id)

    wallet.reload
    expect(wallet.unrealized_pnl).to eq(BigDecimal("20"))
    expect(wallet.equity).to eq(BigDecimal("20"))
  end

  it "prefers Redis LTP when present" do
    allow(PaperTrading::RedisStore).to receive(:get_all_ltp_for_product_ids)
      .and_return({ product.product_id => BigDecimal("110") })

    described_class.perform_now(wallet.id)

    wallet.reload
    expect(wallet.unrealized_pnl).to eq(BigDecimal("40"))
  end
end
