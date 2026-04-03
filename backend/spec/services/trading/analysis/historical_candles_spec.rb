# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::HistoricalCandles do
  let(:market_data) { instance_double("MarketDataAdapter") }
  let(:config) { instance_double("AnalysisConfig", candles_lookback: 5) }

  it "returns normalized candles when the client succeeds" do
    allow(market_data).to receive(:candles).and_return(
      "result" => [
        { "open" => 1, "high" => 2, "low" => 0.5, "close" => 1.5, "volume" => 10, "timestamp" => 100 }
      ]
    )

    rows = described_class.fetch(
      market_data: market_data,
      config:      config,
      symbol:      "BTCUSD",
      resolution:  "5m"
    )

    expect(rows.size).to eq(1)
    expect(rows.first[:close]).to eq(1.5)
  end

  it "returns empty and reports on StandardError" do
    allow(market_data).to receive(:candles).and_raise(StandardError, "rest failure")
    allow(Rails.logger).to receive(:warn)
    allow(Rails.error).to receive(:report)

    result = described_class.fetch(
      market_data: market_data,
      config:      config,
      symbol:      "BTCUSD",
      resolution:  "1h"
    )

    expect(result).to eq([])
    expect(Rails.error).to have_received(:report).with(
      an_object_having_attributes(message: "rest failure"),
      handled: true,
      context: hash_including(
        "component" => "Analysis::HistoricalCandles",
        "symbol" => "BTCUSD",
        "resolution" => "1h"
      )
    )
  end

  it "returns empty and reports on Timeout::Error" do
    allow(market_data).to receive(:candles).and_raise(Timeout::Error, "execution expired")
    allow(Rails.logger).to receive(:warn)
    allow(Rails.error).to receive(:report)

    result = described_class.fetch(
      market_data: market_data,
      config:      config,
      symbol:      "ETHUSD",
      resolution:  "15m"
    )

    expect(result).to eq([])
    expect(Rails.error).to have_received(:report).with(
      instance_of(Timeout::Error),
      handled: true,
      context: hash_including("reason" => "timeout", "symbol" => "ETHUSD")
    )
  end
end
