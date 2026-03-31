# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trade, type: :model do
  describe ".dashboard_pnl_totals" do
    it "aggregates realized PnL, counts, and rolling windows in one query" do
      travel_to Time.zone.parse("2026-03-31 12:00:00 UTC") do
        create(:trade, pnl_usd: 10.0, closed_at: 2.days.ago)
        create(:trade, pnl_usd: 5.0, closed_at: 12.hours.ago)
        create(:trade, pnl_usd: -3.0, closed_at: 30.hours.ago)
        create(:trade, pnl_usd: 2.0, closed_at: nil)

        totals = described_class.dashboard_pnl_totals

        expect(totals[:total_realized]).to eq(14.0)
        expect(totals[:trade_count]).to eq(4)
        expect(totals[:win_count]).to eq(3)
        expect(totals[:daily_pnl]).to eq(5.0)
        expect(totals[:weekly_pnl]).to eq(12.0)
      end
    end
  end

  describe "persistence" do
    it "persists with strategy and regime" do
      trade = create(:trade, strategy: "scalping", regime: "trend")

      expect(trade.reload).to have_attributes(
        strategy: "scalping",
        regime: "trend"
      )
    end
  end

  describe "database constraints" do
    let(:closed_at) { Time.zone.parse("2026-03-31 12:00:00 UTC") }

    it "rejects a row without regime" do
      expect {
        described_class.create!(
          strategy: "multi_timeframe",
          regime: nil,
          symbol: "BTCUSD",
          entry_price: 100,
          exit_price: 99,
          closed_at: closed_at
        )
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects a row without strategy" do
      expect {
        described_class.create!(
          strategy: nil,
          regime: "mean_reversion",
          symbol: "BTCUSD",
          entry_price: 100,
          exit_price: 99,
          closed_at: closed_at
        )
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces uniqueness on symbol, entry_price, exit_price, and closed_at" do
      create(
        :trade,
        symbol: "BTCUSD",
        entry_price: 100,
        exit_price: 99,
        closed_at: closed_at
      )

      duplicate = build(
        :trade,
        symbol: "BTCUSD",
        entry_price: 100,
        exit_price: 99,
        closed_at: closed_at
      )

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
