require "rails_helper"

RSpec.describe Trading::MarketData::CandleBuilder do
  subject(:builder) { described_class.new(symbol: "BTCUSD", interval_seconds: 60) }

  it "returns nil for the first tick (no candle closed yet)" do
    result = builder.on_tick(price: 50000.0, timestamp: 1_711_440_010)
    expect(result).to be_nil
  end

  it "returns a closed candle when a new interval begins" do
    builder.on_tick(price: 50000.0, timestamp: 1_711_440_010)
    builder.on_tick(price: 50100.0, timestamp: 1_711_440_030)
    closed = builder.on_tick(price: 50200.0, timestamp: 1_711_440_070) # next minute
    expect(closed).not_to be_nil
    expect(closed.symbol).to eq("BTCUSD")
    expect(closed.open).to eq(50000.0)
    expect(closed.high).to eq(50100.0)
    expect(closed.low).to eq(50000.0)
    expect(closed.close).to eq(50100.0)
    expect(closed.closed).to be true
  end

  it "tracks high and low within interval" do
    builder.on_tick(price: 50000.0, timestamp: 1_711_440_010)
    builder.on_tick(price: 50500.0, timestamp: 1_711_440_020)
    builder.on_tick(price: 49800.0, timestamp: 1_711_440_030)
    closed = builder.on_tick(price: 50200.0, timestamp: 1_711_440_070)
    expect(closed.high).to eq(50500.0)
    expect(closed.low).to eq(49800.0)
  end

  it "accumulates volume within interval" do
    builder.on_tick(price: 50000.0, timestamp: 1_711_440_010, volume: 1.5)
    builder.on_tick(price: 50100.0, timestamp: 1_711_440_020, volume: 2.0)
    closed = builder.on_tick(price: 50200.0, timestamp: 1_711_440_070)
    expect(closed.volume).to eq(3.5)
  end
end
