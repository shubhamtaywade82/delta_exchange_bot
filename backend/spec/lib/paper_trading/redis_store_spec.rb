# frozen_string_literal: true

require "rails_helper"
require "paper_trading/redis_store"

RSpec.describe PaperTrading::RedisStore do
  describe ".set_ltp / .get_ltp" do
    it "round-trips BigDecimal" do
      described_class.redis.del("delta:ltp:42")
      described_class.set_ltp(42, BigDecimal("123.45"), symbol: nil)
      expect(described_class.get_ltp(42)).to eq(BigDecimal("123.45"))
    end

    it "dual-writes Rails.cache when symbol given" do
      allow(described_class).to receive(:dual_write_ltp_cache?).and_return(true)
      expect(Rails.cache).to receive(:write).with("ltp:BTCUSD", BigDecimal("50"))
      described_class.set_ltp(7, BigDecimal("50"), symbol: "BTCUSD")
    end
  end

  describe ".get_all_ltp_for_product_ids" do
    it "returns a hash of product_id to BigDecimal" do
      described_class.redis.del("delta:ltp:1", "delta:ltp:2")
      described_class.set_ltp(1, BigDecimal("10"), symbol: nil)
      described_class.set_ltp(2, BigDecimal("20"), symbol: nil)
      expect(described_class.get_all_ltp_for_product_ids([1, 2])).to eq(
        1 => BigDecimal("10"),
        2 => BigDecimal("20")
      )
    end
  end
end
