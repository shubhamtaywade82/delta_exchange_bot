# frozen_string_literal: true

require "spec_helper"
require "bot/feed/price_store"

RSpec.describe Bot::Feed::PriceStore do
  subject(:store) { described_class.new }

  it "returns nil for unknown symbol" do
    expect(store.get("BTCUSDT")).to be_nil
  end

  it "stores and retrieves LTP" do
    store.update("BTCUSDT", 45_000.0)
    expect(store.get("BTCUSDT")).to eq(45_000.0)
  end

  it "overwrites with latest value" do
    store.update("BTCUSDT", 45_000.0)
    store.update("BTCUSDT", 46_000.0)
    expect(store.get("BTCUSDT")).to eq(46_000.0)
  end

  it "is thread-safe under concurrent writes" do
    threads = 10.times.map do |i|
      Thread.new { store.update("ETHUSDT", i * 100.0) }
    end
    threads.each(&:join)
    expect(store.get("ETHUSDT")).not_to be_nil
  end
end
