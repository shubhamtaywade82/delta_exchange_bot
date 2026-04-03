# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Learning::CreditAssigner do
  describe ".finalize_trade!" do
    it "writes broker-settled fields so dashboard trade history can show the row" do
      position = create(
        :position,
        symbol: "BTCUSD",
        side: "long",
        status: "filled",
        entry_price: 100.0,
        exit_price: 105.0,
        size: 2.0,
        pnl_usd: 10.0,
        pnl_inr: 850.0,
        entry_time: 1.hour.ago,
        strategy: "multi_timeframe",
        regime: "trending"
      )

      trade = described_class.finalize_trade!(
        position,
        entry_features: { "expected_edge" => "0.01" },
        strategy: "multi_timeframe",
        regime: "trending"
      )

      expect(trade).to have_attributes(
        symbol: "BTCUSD",
        side: "long",
        entry_price: be_within(0.01).of(100.0),
        exit_price: be_within(0.01).of(105.0),
        pnl_usd: be_within(0.01).of(10.0),
        strategy: "multi_timeframe",
        regime: "trending"
      )
      expect(trade.closed_at).to be_present
      expect(trade.duration_seconds).to be_positive
    end
  end
end
