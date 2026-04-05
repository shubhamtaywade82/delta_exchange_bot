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
      expect(trade.position_id).to eq(position.id)
    end

    it "returns the existing trade when finalize_trade! runs again for the same position id" do
      position = create(
        :position,
        symbol: "BTCUSD",
        side: "short",
        status: "closed",
        entry_price: 100.0,
        exit_price: 99.0,
        size: 1.0,
        pnl_usd: 1.0,
        pnl_inr: 85.0,
        entry_time: 1.hour.ago,
        strategy: "scalping",
        regime: "trending"
      )
      first = Trade.create!(
        portfolio_id: position.portfolio_id,
        position_id: position.id,
        symbol: position.symbol,
        side: position.side,
        size: position.size,
        entry_price: position.entry_price,
        exit_price: position.exit_price,
        pnl_usd: position.pnl_usd,
        pnl_inr: position.pnl_inr,
        closed_at: Time.current,
        duration_seconds: 100,
        strategy: "scalping",
        regime: "trending",
        expected_edge: 0,
        realized_pnl: position.pnl_usd,
        realized_edge: 0,
        fees: 0,
        holding_time_ms: 0,
        features: {}
      )

      second = described_class.finalize_trade!(
        position,
        entry_features: {},
        strategy: "scalping",
        regime: "trending"
      )

      expect(second.id).to eq(first.id)
      expect(Trade.where(position_id: position.id).count).to eq(1)
    end
  end
end
