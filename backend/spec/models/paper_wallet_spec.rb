# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperWallet do
  describe "#recompute_from_ledger!" do
    it "replays the same INR balances after rebuilding from ledger rows" do
      wallet = create(:paper_wallet)
      wallet.paper_wallet_ledger_entries.create!(
        entry_type: "margin_reserved",
        direction: "debit",
        amount_inr: BigDecimal("850"),
        meta: {}
      )
      wallet.recompute_from_ledger!

      expected_balance = wallet.balance_inr
      expected_used = wallet.used_margin_inr

      wallet.update_columns(balance_inr: 0, used_margin_inr: 0, available_inr: 0, realized_pnl_inr: 0, equity_inr: 0)
      wallet.recompute_from_ledger!

      expect(wallet.reload.balance_inr).to eq(expected_balance)
      expect(wallet.used_margin_inr).to eq(expected_used)
    end
  end

  describe "#refresh_snapshot!" do
    it "keeps used_margin_inr from the ledger and exposes it as blocked margin in INR terms" do
      wallet = create(:paper_wallet)
      wallet.paper_wallet_ledger_entries.create!(
        entry_type: "margin_reserved",
        direction: "debit",
        amount_inr: BigDecimal("850"),
        meta: {}
      )
      wallet.recompute_from_ledger!

      product = create(:paper_product_snapshot, product_id: 42, mark_price: "100", risk_unit_per_contract: "1")
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
      wallet.reload
      expect(wallet.used_margin_inr).to eq(BigDecimal("850"))
      expect(wallet.available_inr).to eq(wallet.balance_inr - wallet.used_margin_inr)
    end

    it "zeros available_inr when the ledger has no margin locks and balance is zero" do
      wallet = create(:paper_wallet, skip_deposit: true)
      wallet.update_columns(
        balance_inr: 0,
        available_inr: 0,
        used_margin_inr: 0,
        realized_pnl_inr: 0,
        equity_inr: 0,
        unrealized_pnl_inr: 0
      )
      wallet.refresh_snapshot!(ltp_map: {})
      expect(wallet.reload.available_inr).to eq(0)
    end
  end
end
