# frozen_string_literal: true

require "spec_helper"
require "bot/product_cache"

RSpec.describe Bot::ProductCache do
  let(:products) do
    [
      double("Product", id: 1, symbol: "BTCUSDT", contract_value: 0.001),
      double("Product", id: 2, symbol: "ETHUSDT", contract_value: 0.01)
    ]
  end

  subject(:cache) { described_class.new(symbols: %w[BTCUSDT ETHUSDT], products: products) }

  it "looks up product_id by symbol" do
    expect(cache.product_id_for("BTCUSDT")).to eq(1)
  end

  it "looks up contract_value by symbol" do
    expect(cache.contract_value_for("BTCUSDT")).to eq(0.001)
  end

  it "looks up symbol by product_id (inverse lookup)" do
    expect(cache.symbol_for(2)).to eq("ETHUSDT")
  end

  it "raises if a configured symbol is not found in products" do
    expect {
      described_class.new(symbols: %w[BTCUSDT UNKNOWN], products: products)
    }.to raise_error(Bot::ProductCache::MissingProductError, /UNKNOWN/)
  end
end
