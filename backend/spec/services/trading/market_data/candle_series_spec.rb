require "rails_helper"

RSpec.describe Trading::MarketData::CandleSeries do
  let(:candle) do
    Trading::MarketData::Candle.new(
      symbol: "BTCUSD", open: 50000.0, high: 50500.0, low: 49800.0,
      close: 50200.0, volume: 10.0,
      opened_at: 2.minutes.ago, closed_at: 1.minute.ago, closed: true
    )
  end

  before { described_class.reset! }
  after  { described_class.reset! }

  it "stores loaded candles" do
    described_class.load([candle])
    expect(described_class.size).to eq(1)
  end

  it "appends a new candle" do
    described_class.load([])
    described_class.add(candle)
    expect(described_class.all).to include(candle)
  end

  it "caps at MAX_CANDLES by removing oldest" do
    stub_const("Trading::MarketData::CandleSeries::MAX_CANDLES", 3)
    4.times { described_class.add(candle.dup) }
    expect(described_class.size).to eq(3)
  end

  it "returns last N closes" do
    c1 = candle.dup.tap { |c| c.close = 100.0 }
    c2 = candle.dup.tap { |c| c.close = 200.0 }
    described_class.load([c1, c2])
    expect(described_class.closes(2)).to eq([100.0, 200.0])
  end

  it "reset! clears all candles" do
    described_class.load([candle])
    described_class.reset!
    expect(described_class.size).to eq(0)
  end
end
