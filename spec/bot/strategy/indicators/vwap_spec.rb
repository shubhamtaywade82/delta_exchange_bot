# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/indicators/vwap"

RSpec.describe Bot::Strategy::Indicators::VWAP do
  def make_candle(high:, low:, close:, volume:, timestamp: 0)
    { high: high.to_f, low: low.to_f, close: close.to_f,
      volume: volume.to_f, timestamp: timestamp }
  end

  describe ".compute" do
    let(:candles) do
      [
        make_candle(high: 102, low: 98,  close: 100, volume: 10, timestamp: 0),
        make_candle(high: 104, low: 100, close: 102, volume: 20, timestamp: 300),
        make_candle(high: 106, low: 102, close: 104, volume: 30, timestamp: 600),
      ]
    end

    subject(:result) { described_class.compute(candles) }

    it "returns one result per candle" do
      expect(result.size).to eq(3)
    end

    it "first candle VWAP equals its own typical price" do
      tp = (102 + 98 + 100) / 3.0
      expect(result[0][:vwap]).to eq(tp.round(4))
    end

    it "second candle VWAP is volume-weighted avg of first two typical prices" do
      tp0 = (102 + 98  + 100) / 3.0
      tp1 = (104 + 100 + 102) / 3.0
      expected = ((tp0 * 10 + tp1 * 20) / 30.0).round(4)
      expect(result[1][:vwap]).to eq(expected)
    end

    it "returns price_above correctly" do
      expect(result[2][:price_above]).to eq(result[2][:vwap] <= 104.0)
    end

    it "returns nil for zero-volume candles" do
      zero_vol = [make_candle(high: 100, low: 100, close: 100, volume: 0)]
      expect(described_class.compute(zero_vol).first[:vwap]).to be_nil
    end
  end
end
