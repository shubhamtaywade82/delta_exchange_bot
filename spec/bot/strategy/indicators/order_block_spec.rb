# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/indicators/order_block"

RSpec.describe Bot::Strategy::Indicators::OrderBlock do
  def bear_candle(close)
    open = close + 2.0
    { open: open, high: open + 1.0, low: close - 1.0, close: close.to_f }
  end

  def bull_candle(close)
    open = close - 2.0
    { open: open, high: close + 1.0, low: open - 1.0, close: close.to_f }
  end

  describe ".compute" do
    it "identifies a bull OB: last down candle before bullish impulse" do
      candles = [
        bear_candle(102),
        bull_candle(105),
        bull_candle(110),
        bull_candle(115),
      ]
      result = described_class.compute(candles, min_impulse_pct: 1.0, max_ob_age: 10)
      bull_obs = result.select { |ob| ob[:side] == :bull }
      expect(bull_obs).not_to be_empty
    end

    it "identifies a bear OB: last up candle before bearish impulse" do
      candles = [
        bull_candle(102),
        bear_candle(99),
        bear_candle(94),
        bear_candle(89),
      ]
      result = described_class.compute(candles, min_impulse_pct: 1.0, max_ob_age: 10)
      bear_obs = result.select { |ob| ob[:side] == :bear }
      expect(bear_obs).not_to be_empty
    end

    it "marks OB as fresh when price has not traded through it" do
      candles = [
        bear_candle(102),
        bull_candle(108),
        bull_candle(115),
        bull_candle(120),
      ]
      result = described_class.compute(candles, min_impulse_pct: 1.0, max_ob_age: 10)
      bull_ob = result.find { |ob| ob[:side] == :bull }
      expect(bull_ob[:fresh]).to eq(true)
    end

    it "marks OB as not fresh when price trades back through OB low" do
      ob_candle = bear_candle(102)  # high≈103, low≈101
      candles = [
        ob_candle,
        bull_candle(108),
        bull_candle(100),  # last close=100, ob_low=101 → 100 < 101, not fresh
      ]
      result = described_class.compute(candles, min_impulse_pct: 0.1, max_ob_age: 10)
      bull_ob = result.find { |ob| ob[:side] == :bull }
      expect(bull_ob&.dig(:fresh)).not_to eq(true)
    end

    it "excludes OBs older than max_ob_age" do
      candles = [bear_candle(102), bull_candle(110), bull_candle(115)] +
                (0..20).map { |i| bull_candle(115 + i) }
      result = described_class.compute(candles, min_impulse_pct: 0.5, max_ob_age: 5)
      expect(result.all? { |ob| ob[:age] <= 5 }).to be true
    end

    it "returns empty array when fewer than 4 candles" do
      expect(described_class.compute([bear_candle(100)], min_impulse_pct: 0.3, max_ob_age: 10)).to be_empty
    end
  end
end
