# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::ProductCache do
  let(:products) do
    [
      double("Product", id: 1, symbol: "BTCUSD", contract_value: 0.001),
      double("Product", id: 2, symbol: "ETHUSD", contract_value: 0.01)
    ]
  end

  subject(:cache) { described_class.new(symbols: %w[BTCUSD ETHUSD], products: products) }

  it "looks up product_id by symbol" do
    expect(cache.product_id_for("BTCUSD")).to eq(1)
  end

  it "looks up contract_value by symbol" do
    expect(cache.contract_value_for("BTCUSD")).to eq(0.001)
  end

  it "looks up lot_size by symbol (same multiplier as contract_value for Delta perps)" do
    expect(cache.lot_size_for("BTCUSD")).to eq(0.001)
  end

  it "looks up symbol by product_id (inverse lookup)" do
    expect(cache.symbol_for(2)).to eq("ETHUSD")
  end

  it "raises if a configured symbol is not found in products" do
    expect {
      described_class.new(symbols: %w[BTCUSD UNKNOWN], products: products)
    }.to raise_error(Bot::ProductCache::MissingProductError, /UNKNOWN/)
  end

  it "raises MissingProductError (not KeyError) for unknown symbol lookup" do
    expect { cache.product_id_for("UNKNOWN") }.to raise_error(Bot::ProductCache::MissingProductError, /UNKNOWN/)
  end

  it "returns nil for symbol_for with unconfigured product_id" do
    expect(cache.symbol_for(999)).to be_nil
  end

  it "knows about configured product_ids" do
    expect(cache.known_product_id?(1)).to be(true)
    expect(cache.known_product_id?(2)).to be(true)
    expect(cache.known_product_id?(999)).to be(false)
  end
end
