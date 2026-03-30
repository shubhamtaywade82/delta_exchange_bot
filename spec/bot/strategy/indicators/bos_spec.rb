# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/indicators/bos"

RSpec.describe Bot::Strategy::Indicators::BOS do
  def candle(high:, low:, close:)
    { high: high.to_f, low: low.to_f, close: close.to_f }
  end

  describe ".compute" do
    let(:ranging) do
      (0..9).map { candle(high: 105.0, low: 95.0, close: 100.0) }
    end

    it "returns one result per candle" do
      result = described_class.compute(ranging, swing_lookback: 5)
      expect(result.size).to eq(ranging.size)
    end

    it "returns confirmed: false before enough lookback candles" do
      result = described_class.compute(ranging, swing_lookback: 5)
      expect(result.first[:confirmed]).to eq(false)
    end

    it "detects bullish BOS when close breaks above swing high" do
      candles = ranging + [candle(high: 120.0, low: 100.0, close: 115.0)]
      result  = described_class.compute(candles, swing_lookback: 5)
      last    = result.last
      expect(last[:direction]).to eq(:bullish)
      expect(last[:confirmed]).to eq(true)
      expect(last[:level]).to eq(105.0)
    end

    it "detects bearish BOS when close breaks below swing low" do
      candles = ranging + [candle(high: 100.0, low: 80.0, close: 85.0)]
      result  = described_class.compute(candles, swing_lookback: 5)
      last    = result.last
      expect(last[:direction]).to eq(:bearish)
      expect(last[:confirmed]).to eq(true)
      expect(last[:level]).to eq(95.0)
    end

    it "returns confirmed: false when close stays within range" do
      candles = ranging + [candle(high: 104.0, low: 97.0, close: 101.0)]
      result  = described_class.compute(candles, swing_lookback: 5)
      expect(result.last[:confirmed]).to eq(false)
    end
  end
end
