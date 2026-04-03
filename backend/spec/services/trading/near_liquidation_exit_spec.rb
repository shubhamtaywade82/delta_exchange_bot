# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::NearLiquidationExit do
  let(:session) { create(:trading_session, capital: 5000.0) }
  let(:client) { instance_double(DeltaExchange::Client) }

  before do
    allow(Trading::EmergencyShutdown).to receive(:force_exit_position)
  end

  describe "#check!" do
    around do |example|
      previous_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = previous_cache
    end

    it "does nothing when liquidation_price is absent" do
      position = create(
        :position,
        portfolio: session.portfolio,
        symbol: "BTCUSD",
        side: "long",
        status: "filled",
        liquidation_price: nil,
        entry_price: 100_000.0,
        size: 1.0,
        leverage: 10
      )
      Rails.cache.write("ltp:BTCUSD", 99_000.0)

      described_class.new(position, client).check!

      expect(Trading::EmergencyShutdown).not_to have_received(:force_exit_position)
    end

    it "does nothing when LTP is missing or non-positive" do
      position = create(
        :position,
        portfolio: session.portfolio,
        symbol: "BTCUSD",
        side: "long",
        status: "filled",
        liquidation_price: 90_000.0,
        entry_price: 100_000.0,
        size: 1.0,
        leverage: 10
      )

      described_class.new(position, client).check!

      expect(Trading::EmergencyShutdown).not_to have_received(:force_exit_position)
    end

    it "forces exit for a long when price is within BUFFER_PCT of liquidation" do
      position = create(
        :position,
        portfolio: session.portfolio,
        symbol: "BTCUSD",
        side: "long",
        status: "filled",
        liquidation_price: 90_000.0,
        entry_price: 100_000.0,
        size: 1.0,
        leverage: 10
      )
      Rails.cache.write("ltp:BTCUSD", 99_000.0)

      described_class.new(position, client).check!

      expect(Trading::EmergencyShutdown).to have_received(:force_exit_position).with(position, client)
    end

    it "does not exit a long when price is far above liquidation" do
      position = create(
        :position,
        portfolio: session.portfolio,
        symbol: "BTCUSD",
        side: "long",
        status: "filled",
        liquidation_price: 50_000.0,
        entry_price: 100_000.0,
        size: 1.0,
        leverage: 10
      )
      Rails.cache.write("ltp:BTCUSD", 100_000.0)

      described_class.new(position, client).check!

      expect(Trading::EmergencyShutdown).not_to have_received(:force_exit_position)
    end

    it "forces exit for a short when price is within BUFFER_PCT of liquidation" do
      position = create(
        :position,
        portfolio: session.portfolio,
        symbol: "ETHUSD",
        side: "short",
        status: "filled",
        liquidation_price: 3100.0,
        entry_price: 3000.0,
        size: 1.0,
        leverage: 10
      )
      Rails.cache.write("ltp:ETHUSD", 3001.0)

      described_class.new(position, client).check!

      expect(Trading::EmergencyShutdown).to have_received(:force_exit_position).with(position, client)
    end
  end
end
