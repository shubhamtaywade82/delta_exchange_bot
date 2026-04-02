# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Strategy::Indicators::FairValueGap do
  def c(o, h, l, cl)
    { open: o, high: h, low: l, close: cl, volume: 1.0, timestamp: 0 }
  end

  it "detects a bullish FVG when the third candle gaps above the first" do
    candles = [
      c(10, 11, 9, 10),
      c(10, 12, 9.5, 11),
      c(12, 14, 12.5, 13)
    ]
    gaps = described_class.detect(candles, max_age: 10)
    expect(gaps.size).to eq(1)
    expect(gaps.first[:type]).to eq(:bullish)
    expect(gaps.first[:bottom]).to eq(11.0)
    expect(gaps.first[:top]).to eq(12.5)
  end

  it "detects a bearish FVG when the third candle gaps below the first" do
    candles = [
      c(20, 21, 19, 20),
      c(19, 20, 18, 19),
      c(17, 18, 16, 17)
    ]
    gaps = described_class.detect(candles, max_age: 10)
    expect(gaps.size).to eq(1)
    expect(gaps.first[:type]).to eq(:bearish)
  end
end
