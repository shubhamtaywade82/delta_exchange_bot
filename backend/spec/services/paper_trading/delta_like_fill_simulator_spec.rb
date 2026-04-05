# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::DeltaLikeFillSimulator do
  describe ".plan_slices" do
    it "returns one taker slice for a market buy when depth covers size" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("PAPER_MARKET_DEPTH", "100").and_return("100")
      allow(ENV).to receive(:fetch).with("PAPER_SPREAD_BPS", "0").and_return("0")

      slices = described_class.plan_slices(
        ltp: BigDecimal("50000"),
        side: "buy",
        order_type: "market_order",
        size: 2,
        limit_price: nil,
        spread_bps: BigDecimal("0"),
        market_depth: BigDecimal("100")
      )

      expect(slices.size).to eq(1)
      expect(slices.first.qty).to eq(2)
      expect(slices.first.liquidity).to eq(:taker)
      expect(slices.first.price).to be > BigDecimal("0")
    end

    it "returns no slices when depth is zero (empty book)" do
      slices = described_class.plan_slices(
        ltp: BigDecimal("50000"),
        side: "buy",
        order_type: "market_order",
        size: 1,
        limit_price: nil,
        spread_bps: BigDecimal("0"),
        market_depth: BigDecimal("0")
      )

      expect(slices).to eq([])
    end
  end
end
