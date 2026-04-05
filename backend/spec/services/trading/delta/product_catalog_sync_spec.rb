# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Delta::ProductCatalogSync do
  describe ".sync_one!" do
    it "updates symbol_config from product and ticker" do
      config = create(:symbol_config, symbol: "BTCUSD", enabled: true, product_id: nil, metadata: {})

      product = instance_double(
        DeltaExchange::Models::Product,
        id: "27",
        contract_type: "perpetual_futures",
        tick_size: "0.5",
        contract_value: "0.001",
        lot_size: nil
      )
      allow(product).to receive(:contract_lot_multiplier).and_return(BigDecimal("0.001"))

      ticker = instance_double(
        DeltaExchange::Models::Ticker,
        mark_price: "50000.5",
        close: "49990"
      )

      allow(DeltaExchange::Models::Product).to receive(:find).with("BTCUSD").and_return(product)
      allow(DeltaExchange::Models::Ticker).to receive(:find).with("BTCUSD").and_return(ticker)

      expect(described_class.sync_one!(config)).to be true
      config.reload
      expect(config.product_id).to eq(27)
      expect(config.tick_size).to eq(BigDecimal("0.5"))
      expect(config.contract_type).to eq("perpetual_futures")
      expect(config.last_mark_price).to eq(BigDecimal("50000.5"))
      expect(config.last_close_price).to eq(BigDecimal("49990"))
      expect(config.metadata["contract_lot_multiplier"]).to eq("0.001")
      expect(config.fetched_at).to be_present
    end

    it "returns false on API error" do
      config = create(:symbol_config, symbol: "ETHUSD", enabled: true)
      allow(DeltaExchange::Models::Product).to receive(:find).and_raise(StandardError, "network")
      allow(Rails.logger).to receive(:warn)
      allow(Rails.error).to receive(:report)

      expect(described_class.sync_one!(config)).to be false

      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "network"),
        handled: true,
        context: hash_including("component" => "Delta::ProductCatalogSync", "symbol" => "ETHUSD")
      )
    end
  end
end
