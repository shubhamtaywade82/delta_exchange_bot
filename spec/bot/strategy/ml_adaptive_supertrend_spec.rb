# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/ml_adaptive_supertrend"

RSpec.describe Bot::Strategy::MlAdaptiveSupertrend do
  def candle(ts, open, high, low, close)
    { open: open, high: high, low: low, close: close, timestamp: ts }
  end

  describe ".compute" do
    it "returns nil direction until the indicator warms up" do
      candles = 15.times.map { |i| candle(i, 100, 101, 99, 100.5) }
      out = described_class.compute(
        candles,
        atr_len: 10, factor: 1.0, training_period: 20
      )
      expect(out.first[:direction]).to be_nil
      expect(out.last[:direction]).to be_nil
    end

    it "produces a directional signal once training window is satisfied" do
      candles = 50.times.map { |i| candle(i, 100 + i, 101 + i, 99 + i, 100.5 + i) }
      out = described_class.compute(
        candles,
        atr_len: 10, factor: 1.0, training_period: 20
      )
      expect(%i[bullish bearish]).to include(out.last[:direction])
    end

    it "marks strong uptrend as bullish on the last bar" do
      candles = 120.times.map do |i|
        base = 100.0 + (i * 2.0)
        candle(i, base - 0.5, base + 1.0, base - 1.0, base)
      end
      out = described_class.compute(
        candles,
        atr_len: 10, factor: 1.0, training_period: 100
      )
      expect(out.last[:direction]).to eq(:bullish)
    end
  end
end
