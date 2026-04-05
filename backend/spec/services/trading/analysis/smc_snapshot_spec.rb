# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::SmcSnapshot do
  def candle(i)
    t = Time.utc(2024, 6, 1, 10, 0, 0) + i.minutes
    {
      timestamp: t.to_i,
      open: 100.0 + i * 0.01,
      high: 101.0 + i * 0.01,
      low: 99.0 + i * 0.01,
      close: 100.5 + i * 0.01,
      volume: 10.0
    }
  end

  describe ".build" do
    it "includes smc_confluence from the Pine-parity engine on the last bar" do
      # MS_SWING default 10 needs >= 40 bars for structure_sequence; VP needs >= 100 for full profile.
      candles = 120.times.map { |i| candle(i) }
      snap = described_class.build(candles: candles, resolution: "5m")
      expect(snap["smc_confluence"]).to be_a(Hash)
      expect(snap["smc_confluence"]["bar_index"]).to eq(119)
      expect(snap["smc_confluence"]).to have_key("long_score")
      expect(snap["smc_confluence"]).to have_key("structure_bias")
    end

    it "passes MS_SWING into SmcSwingStructure so HH/HL labels use the same pivot length as confluence Layer 2" do
      candles = 12.times.map { |i| candle(i) }
      allow(Trading::Analysis::SmcSwingStructure).to receive(:analyze).and_return(
        Trading::Analysis::SmcSwingStructure.default_empty
      )
      described_class.build(candles: candles, resolution: "5m")
      expect(Trading::Analysis::SmcSwingStructure).to have_received(:analyze).with(
        candles,
        swing: Trading::Analysis::SmcSnapshot::MS_SWING
      )
    end

    it "sets smc_confluence to nil when candle data is insufficient" do
      snap = described_class.build(candles: 3.times.map { |i| candle(i) }, resolution: "5m")
      expect(snap["error"]).to eq("insufficient_candles")
      expect(snap["smc_confluence"]).to be_nil
    end
  end
end
