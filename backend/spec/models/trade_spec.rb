# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trade, type: :model do
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
