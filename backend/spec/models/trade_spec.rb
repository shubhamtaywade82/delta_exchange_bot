# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trade, type: :model do
  describe ".broker_settled_calendar_days" do
    it "returns unique calendar days for symbol-backed closed trades, newest first" do
      day_a = Date.new(2026, 3, 30)
      day_b = Date.new(2026, 3, 31)
      create(:trade, symbol: "BTCUSD", closed_at: day_a.in_time_zone.change(hour: 10), pnl_usd: 1)
      create(:trade, symbol: "ETHUSD", closed_at: day_a.in_time_zone.change(hour: 11), pnl_usd: 1)
      create(:trade, symbol: "BTCUSD", closed_at: day_b.in_time_zone.change(hour: 12), pnl_usd: 1)
      create(:trade, symbol: nil, closed_at: day_b.in_time_zone.change(hour: 12), pnl_usd: 0)

      expect(described_class.broker_settled_calendar_days).to eq([day_b, day_a])
    end
  end

  describe ".dashboard_pnl_totals" do
    it "aggregates effective realized PnL, counts, and rolling windows" do
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

    it "uses inferred PnL when stored pnl_usd is zero" do
      allow(Trading::Risk::PositionLotSize).to receive(:multiplier_for).and_return(1)
      travel_to Time.zone.parse("2026-03-31 12:00:00 UTC") do
        create(:trade,
               pnl_usd: 0,
               symbol: "BTCUSD",
               side: "short",
               size: 1,
               entry_price: 100,
               exit_price: 105,
               closed_at: Time.current,
               strategy: "multi_timeframe",
               regime: "trending")

        totals = described_class.dashboard_pnl_totals

        expect(totals[:total_realized]).to eq(-5.0)
        expect(totals[:win_count]).to eq(0)
      end
    end
  end

  describe "#effective_pnl_usd" do
    it "returns stored pnl_usd when non-zero" do
      trade = build(:trade, pnl_usd: 3.5)
      expect(trade.effective_pnl_usd).to eq(BigDecimal("3.5"))
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
