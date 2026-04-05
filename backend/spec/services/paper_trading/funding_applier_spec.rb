# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::FundingApplier do
  let(:wallet) { create(:paper_wallet, seed_inr: BigDecimal("50000")) }
  let(:product) do
    create(:paper_product_snapshot,
      symbol: "SOLUSD",
      contract_value: BigDecimal("1"),
      risk_unit_per_contract: BigDecimal("1"),
      default_leverage: 10)
  end

  it "books funding debit for long positions" do
    PaperPosition.create!(
      paper_wallet: wallet,
      paper_product_snapshot: product,
      side: "buy",
      net_quantity: 2,
      avg_entry_price: BigDecimal("80"),
      risk_unit_per_contract: BigDecimal("1"),
      leverage: 10
    )

    described_class.new(wallet: wallet, usd_inr_rate: 85).call(
      funding_rate: BigDecimal("0.001"),
      mark_prices: { product.product_id => BigDecimal("100") }
    )

    funding = wallet.reload.paper_wallet_ledger_entries.where(entry_type: "funding")
    expect(funding.count).to eq(1)
    expect(funding.first.direction).to eq("debit")
    expect(funding.first.amount_inr).to eq(BigDecimal("17"))
  end
end
