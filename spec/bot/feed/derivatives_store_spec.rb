# frozen_string_literal: true

require "spec_helper"
require "bot/feed/derivatives_store"

RSpec.describe Bot::Feed::DerivativesStore do
  let(:products) { double("Products") }
  let(:logger)   { double("Logger", error: nil, debug: nil) }
  subject(:store) do
    described_class.new(products: products, symbols: ["BTCUSD"],
                        poll_interval: 999, logger: logger)
  end

  describe "#get with no data" do
    it "returns nil OI fields and false for funding_extreme" do
      result = store.get("BTCUSD")
      expect(result[:oi_usd]).to be_nil
      expect(result[:oi_trend]).to be_nil
      expect(result[:funding_rate]).to be_nil
      expect(result[:funding_extreme]).to eq(false)
    end
  end

  describe "#update_funding_rate" do
    it "stores funding rate and marks extreme when above threshold" do
      store.update_funding_rate("BTCUSD", rate: 0.0006)
      result = store.get("BTCUSD")
      expect(result[:funding_rate]).to eq(0.0006)
      expect(result[:funding_extreme]).to eq(true)
    end

    it "marks not extreme when below threshold" do
      store.update_funding_rate("BTCUSD", rate: 0.0003)
      expect(store.get("BTCUSD")[:funding_extreme]).to eq(false)
    end
  end

  describe "#update_oi" do
    it "stores OI and detects rising trend on second call" do
      store.update_oi("BTCUSD", oi_usd: 1_000_000.0)
      store.update_oi("BTCUSD", oi_usd: 1_100_000.0)
      result = store.get("BTCUSD")
      expect(result[:oi_usd]).to eq(1_100_000.0)
      expect(result[:oi_trend]).to eq(:rising)
    end

    it "detects falling trend when OI decreases" do
      store.update_oi("BTCUSD", oi_usd: 1_100_000.0)
      store.update_oi("BTCUSD", oi_usd: 900_000.0)
      expect(store.get("BTCUSD")[:oi_trend]).to eq(:falling)
    end

    it "defaults to rising on first OI update" do
      store.update_oi("BTCUSD", oi_usd: 500_000.0)
      expect(store.get("BTCUSD")[:oi_trend]).to eq(:rising)
    end
  end

  describe "#poll_oi" do
    it "fetches OI from ticker and calls update_oi" do
      allow(products).to receive(:ticker).with("BTCUSD").and_return(
        { "oi_value_usd" => "4200000.5", "funding_rate" => "0.0001" }
      )
      store.poll_oi
      expect(store.get("BTCUSD")[:oi_usd]).to eq(4_200_000.5)
    end

    it "skips symbol if ticker has no oi_value_usd" do
      allow(products).to receive(:ticker).with("BTCUSD").and_return({})
      expect { store.poll_oi }.not_to raise_error
      expect(store.get("BTCUSD")[:oi_usd]).to be_nil
    end
  end
end
