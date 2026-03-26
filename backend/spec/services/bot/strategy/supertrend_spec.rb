# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Strategy::Supertrend do
  # 15 synthetic bars: trending up then reversing
  let(:candles) do
    prices = [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 109, 107, 104, 100]
    prices.map do |c|
      { open: c - 0.5, high: c + 1.0, low: c - 1.0, close: c.to_f }
    end
  end

  subject(:result) { described_class.compute(candles, atr_period: 3, multiplier: 1.5) }

  it "returns one result per candle" do
    expect(result.size).to eq(candles.size)
  end

  it "returns hash with :direction and :line keys" do
    expect(result.last).to include(:direction, :line)
  end

  it "reports bullish direction during uptrend" do
    expect(result[5][:direction]).to eq(:bullish)
  end

  it "flips to bearish after a significant drop" do
    expect(result.last[:direction]).to eq(:bearish)
  end

  it "returns nil direction for bars before enough data" do
    expect(result.first[:direction]).to be_nil
  end

  it "raises ArgumentError with fewer than 2 candles" do
    expect { described_class.compute([candles.first], atr_period: 3, multiplier: 1.5) }
      .to raise_error(ArgumentError)
  end
end
