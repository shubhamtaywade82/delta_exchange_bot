# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperWallet do
  describe "#risk_sizing_equity_usd" do
    it "sums cash_balance and realized_pnl excluding unrealized" do
      wallet = build(
        :paper_wallet,
        cash_balance: "50_000",
        realized_pnl: "2_500",
        unrealized_pnl: "99_999",
        equity: "152_499"
      )
      expect(wallet.risk_sizing_equity_usd).to eq(BigDecimal("52500"))
    end
  end

  describe "#refresh_snapshot!" do
    it "sets reserved_margin from open positions and zeros when flat" do
      wallet = create(
        :paper_wallet,
        cash_balance: "1000",
        realized_pnl: "0",
        unrealized_pnl: "0",
        equity: "1000",
        reserved_margin: "999"
      )
      product = create(:paper_product_snapshot, product_id: 42, mark_price: "100", risk_unit_per_contract: "1")

      wallet.refresh_snapshot!(ltp_map: {})
      expect(wallet.reload.reserved_margin).to eq(0)

      PaperPosition.create!(
        paper_wallet: wallet,
        paper_product_snapshot: product,
        side: "buy",
        net_quantity: 1,
        avg_entry_price: "100",
        risk_unit_per_contract: "1",
        leverage: 10
      )
      wallet.refresh_snapshot!(ltp_map: { 42 => BigDecimal("100") })
      expect(wallet.reload.reserved_margin).to eq(BigDecimal("10"))
    end
  end
end
