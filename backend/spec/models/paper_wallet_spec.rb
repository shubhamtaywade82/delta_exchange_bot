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
end
