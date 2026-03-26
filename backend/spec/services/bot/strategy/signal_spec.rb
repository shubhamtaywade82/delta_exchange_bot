# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Strategy::Signal do
  subject(:signal) do
    described_class.new(symbol: "BTCUSD", side: :long, entry_price: 45_000.0, candle_ts: 1_000_000)
  end

  it "exposes all fields" do
    expect(signal.symbol).to eq("BTCUSD")
    expect(signal.side).to eq(:long)
    expect(signal.entry_price).to eq(45_000.0)
    expect(signal.candle_ts).to eq(1_000_000)
  end

  it "returns true for long?" do
    expect(signal.long?).to be(true)
    expect(signal.short?).to be(false)
  end

  it "returns true for short? on a short signal" do
    short_signal = described_class.new(symbol: "ETHUSD", side: :short, entry_price: 3000.0, candle_ts: 2)
    expect(short_signal.short?).to be(true)
    expect(short_signal.long?).to be(false)
  end
end
