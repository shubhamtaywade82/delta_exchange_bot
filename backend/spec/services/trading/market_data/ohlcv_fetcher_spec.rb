# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::MarketData::OhlcvFetcher do
  let(:client) { double("DeltaExchange::Client") }

  it "returns candles when the client succeeds" do
    allow(client).to receive(:get_ohlcv).and_return([
      { open: 1, high: 2, low: 0.5, close: 1.5, volume: 10, time: 1_700_000_000 }
    ])

    candles = described_class.new(client: client).fetch(symbol: "BTCUSD", resolution: "1m", limit: 1)

    expect(candles.size).to eq(1)
    expect(candles.first.close).to eq(1.5)
  end

  it "returns an empty array and reports when the client fails" do
    allow(client).to receive(:get_ohlcv).and_raise(StandardError, "api error")
    allow(Rails.logger).to receive(:warn)
    allow(Rails.error).to receive(:report)

    result = described_class.new(client: client).fetch(symbol: "ETHUSD", resolution: "5m")

    expect(result).to eq([])
    expect(Rails.error).to have_received(:report).with(
      an_object_having_attributes(message: "api error"),
      handled: true,
      context: hash_including(
        "component" => "MarketData::OhlcvFetcher",
        "symbol" => "ETHUSD",
        "resolution" => "5m"
      )
    )
  end
end
