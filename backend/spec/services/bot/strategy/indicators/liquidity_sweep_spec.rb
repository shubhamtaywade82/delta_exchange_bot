# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Strategy::Indicators::LiquiditySweep do
  describe ".grab_vs_sweep (metrics)" do
    it "returns ratios and an event_style string for buy-side liquidity" do
      m = described_class.send(
        :grab_vs_sweep,
        side: :buy_side,
        level: 100.0,
        open: 99.0,
        high: 102.0,
        low: 98.0,
        close: 99.0,
        range: 4.0
      )
      expect(m[:wick_penetration_ratio]).to eq(0.5)
      expect(m[:close_rejection_depth_ratio]).to eq(0.25)
      expect(m[:event_style]).to be_a(String)
    end
  end
end
