# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::FundingMonitor do
  describe ".check_all" do
    let(:products) { instance_double(DeltaExchange::Resources::Products) }
    let(:client)   { instance_double(DeltaExchange::Client, products: products) }

    it "reads funding from the public ticker endpoint (not a missing client method)" do
      position = instance_double(Position, symbol: "BTCUSD")
      allow(Position).to receive(:active).and_return([position])

      allow(products).to receive(:ticker).with("BTCUSD").and_return(
        { result: { "funding_rate" => "0.0002" } }
      )

      expect(Rails.logger).not_to receive(:warn).with(/Could not fetch funding rate/)

      described_class.check_all(client: client)
    end

    it "logs and continues when ticker fetch fails" do
      position = instance_double(Position, symbol: "ETHUSD")
      allow(Position).to receive(:active).and_return([position])

      allow(products).to receive(:ticker).and_raise(StandardError, "network down")

      expect(Rails.logger).to receive(:warn).with(
        "[FundingMonitor] Could not fetch funding rate for ETHUSD: network down"
      )

      described_class.check_all(client: client)
    end
  end
end
