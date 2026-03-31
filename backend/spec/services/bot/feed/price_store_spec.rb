# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Feed::PriceStore do
  subject(:store) { described_class.new }

  before do
    r = Redis.new
    r.keys("#{described_class::REDIS_KEY_PREFIX}*").each { |k| r.del(k) }
  end

  it "returns nil for unknown symbol" do
    expect(store.get("BTCUSD")).to be_nil
  end

  it "stores and retrieves LTP" do
    store.update("BTCUSD", 45_000.0)
    expect(store.get("BTCUSD")).to eq(45_000.0)
  end

  it "overwrites with latest value" do
    store.update("BTCUSD", 45_000.0)
    store.update("BTCUSD", 46_000.0)
    expect(store.get("BTCUSD")).to eq(46_000.0)
  end

  it "is thread-safe under concurrent writes" do
    threads = 10.times.map do |i|
      Thread.new { store.update("ETHUSD", i * 100.0) }
    end
    threads.each(&:join)
    expect(store.get("ETHUSD")).not_to be_nil
  end
end
