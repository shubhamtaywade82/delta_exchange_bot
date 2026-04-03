# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::RepriceWalletJob do
  let(:wallet) { create(:paper_wallet) }
  let(:product) { create(:paper_product_snapshot, product_id: 99, mark_price: "100", close_price: "100", risk_unit_per_contract: "1") }

  before do
    PaperWalletLedgerEntry.create!(
      paper_wallet: wallet,
      entry_type: "margin_reserved",
      direction: "debit",
      amount_inr: BigDecimal("15_300"),
      meta: {}
    )
    wallet.reload.recompute_from_ledger!

    PaperPosition.create!(
      paper_wallet: wallet,
      paper_product_snapshot: product,
      side: "buy",
      net_quantity: 2,
      avg_entry_price: "90",
      risk_unit_per_contract: "1",
      leverage: 1
    )
  end

  it "rebuilds equity from DB prices when Redis LTP is empty" do
    allow(PaperTrading::RedisStore).to receive(:get_all_ltp_for_product_ids).and_return({})

    described_class.perform_now(wallet.id)

    wallet.reload
    expect(wallet.unrealized_pnl_inr).to eq(BigDecimal("1700"))
    expect(wallet.used_margin_inr).to eq(BigDecimal("15_300"))
    expect(wallet.equity_inr).to be > wallet.balance_inr
  end

  it "prefers Redis LTP when present" do
    allow(PaperTrading::RedisStore).to receive(:get_all_ltp_for_product_ids)
      .and_return({ product.product_id => BigDecimal("110") })

    described_class.perform_now(wallet.id)

    wallet.reload
    expect(wallet.unrealized_pnl_inr).to eq(BigDecimal("3400"))
    expect(wallet.used_margin_inr).to eq(BigDecimal("15_300"))
  end
end
