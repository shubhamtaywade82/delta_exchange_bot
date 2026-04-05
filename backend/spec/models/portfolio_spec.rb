# frozen_string_literal: true

require "rails_helper"

RSpec.describe Portfolio, type: :model do
  describe "#apply_fill_and_sync!" do
    let(:portfolio) do
      create(:portfolio, balance: BigDecimal("1000"), available_balance: BigDecimal("1000"), used_margin: BigDecimal("0"))
    end
    let(:session) { create(:trading_session, portfolio: portfolio) }
    let(:order) { create(:order, trading_session: session, portfolio: portfolio) }
    let(:fill) { create(:fill, order: order, fee: BigDecimal("10"), quantity: BigDecimal("1")) }

    it "reduces balance by trading fee when realized pnl delta is zero" do
      portfolio.apply_fill_and_sync!(fill, delta_realized: BigDecimal("0"))

      expect(portfolio.reload.balance).to eq(BigDecimal("990"))
      entry = portfolio.portfolio_ledger_entries.find_by!(fill_id: fill.id)
      expect(entry.realized_pnl_delta).to eq(BigDecimal("0"))
      expect(entry.balance_delta).to eq(BigDecimal("-10"))
    end

    it "combines realized pnl and fee into wallet delta" do
      portfolio.apply_fill_and_sync!(fill, delta_realized: BigDecimal("100"))

      expect(portfolio.reload.balance).to eq(BigDecimal("1090"))
      entry = portfolio.portfolio_ledger_entries.find_by!(fill_id: fill.id)
      expect(entry.realized_pnl_delta).to eq(BigDecimal("100"))
      expect(entry.balance_delta).to eq(BigDecimal("90"))
    end
  end
end
