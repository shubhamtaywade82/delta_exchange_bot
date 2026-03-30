# frozen_string_literal: true

require "spec_helper"
require "bot/feed/cvd_store"

RSpec.describe Bot::Feed::CvdStore do
  subject(:store) { described_class.new(window: 4) }

  describe "#record_trade and #get" do
    it "starts with zero delta and neutral trend" do
      result = store.get("BTCUSD")
      expect(result[:cumulative_delta]).to eq(0.0)
      expect(result[:delta_trend]).to eq(:neutral)
    end

    it "accumulates positive delta for buy trades" do
      store.record_trade("BTCUSD", side: "buy", size: 10)
      store.record_trade("BTCUSD", side: "buy", size: 5)
      expect(store.get("BTCUSD")[:cumulative_delta]).to eq(15.0)
    end

    it "accumulates negative delta for sell trades" do
      store.record_trade("BTCUSD", side: "sell", size: 8)
      expect(store.get("BTCUSD")[:cumulative_delta]).to eq(-8.0)
    end

    it "returns bullish trend when window delta is positive" do
      store.record_trade("BTCUSD", side: "buy",  size: 10)
      store.record_trade("BTCUSD", side: "buy",  size: 5)
      store.record_trade("BTCUSD", side: "sell", size: 2)
      expect(store.get("BTCUSD")[:delta_trend]).to eq(:bullish)
    end

    it "returns bearish trend when window delta is negative" do
      store.record_trade("BTCUSD", side: "sell", size: 10)
      store.record_trade("BTCUSD", side: "sell", size: 5)
      store.record_trade("BTCUSD", side: "buy",  size: 2)
      expect(store.get("BTCUSD")[:delta_trend]).to eq(:bearish)
    end

    it "evicts old trades beyond the window" do
      # window=4: add 4 buys then 4 sells — only sells in window
      4.times { store.record_trade("BTCUSD", side: "buy",  size: 10) }
      4.times { store.record_trade("BTCUSD", side: "sell", size: 10) }
      expect(store.get("BTCUSD")[:delta_trend]).to eq(:bearish)
    end

    it "tracks each symbol independently" do
      store.record_trade("BTCUSD", side: "buy",  size: 10)
      store.record_trade("ETHUSD", side: "sell", size: 5)
      expect(store.get("BTCUSD")[:delta_trend]).to eq(:bullish)
      expect(store.get("ETHUSD")[:delta_trend]).to eq(:bearish)
    end
  end
end
