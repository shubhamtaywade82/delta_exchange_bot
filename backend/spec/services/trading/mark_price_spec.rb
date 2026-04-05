# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::MarkPrice do
  let(:portfolio) { create(:portfolio) }
  let(:position) do
    create(
      :position,
      portfolio: portfolio,
      symbol: "BTCUSD",
      side: "long",
      status: "filled",
      entry_price: 50_000.0,
      product_id: 84,
      size: 1.0,
      leverage: 10
    )
  end

  around do |example|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous_cache
  end

  before do
    r = Redis.current
    r.keys("#{Bot::Feed::PriceStore::REDIS_KEY_PREFIX}*").each { |k| r.del(k) }
  end

  describe ".for_synthetic_exit" do
    it "prefers Rails.cache mark over ltp" do
      Rails.cache.write("mark:BTCUSD", 50_100)
      Rails.cache.write("ltp:BTCUSD", 51_000)
      expect(described_class.for_synthetic_exit(position)).to eq(BigDecimal("50100"))
    end

    it "uses ltp cache when mark is absent" do
      Rails.cache.write("ltp:BTCUSD", 51_000)
      expect(described_class.for_synthetic_exit(position)).to eq(BigDecimal("51000"))
    end

    it "uses PriceStore when cache keys are empty" do
      allow(PaperTrading::RedisStore).to receive(:get_ltp).with(position.product_id).and_return(nil)
      Bot::Feed::PriceStore.new.update("BTCUSD", 52_222.5)
      expect(described_class.for_synthetic_exit(position)).to eq(BigDecimal("52222.5"))
    end

    it "uses paper Redis via SymbolConfig product_id when position.product_id is blank" do
      position.update_column(:product_id, nil)
      SymbolConfig.create!(
        symbol: "BTCUSD",
        product_id: 84,
        last_mark_price: 50_000.0,
        enabled: true
      )
      allow(PaperTrading::RedisStore).to receive(:get_ltp).with(84).and_return(66_200.5)
      expect(described_class.for_synthetic_exit(position)).to eq(BigDecimal("66200.5"))
    end

    it "uses SymbolConfig catalog prices when higher-priority sources are absent" do
      SymbolConfig.create!(
        symbol: "BTCUSD",
        product_id: 84,
        last_mark_price: 48_888.0,
        last_close_price: 48_000.0,
        enabled: true
      )
      expect(described_class.for_synthetic_exit(position)).to eq(BigDecimal("48888"))
    end

    it "falls back to entry_price when no other source exists" do
      expect(described_class.for_synthetic_exit(position)).to eq(BigDecimal("50000"))
    end

    it "returns nil without entry fallback when no live or catalog price exists" do
      expect(described_class.for_synthetic_exit(position, fallback_entry_price: false)).to be_nil
    end
  end
end
