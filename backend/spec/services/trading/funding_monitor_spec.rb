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
      allow(Rails.logger).to receive(:warn)
      allow(Rails.error).to receive(:report)

      described_class.check_all(client: client)

      expect(Rails.logger).to have_received(:warn).with(
        a_string_matching(/\[FundingMonitor\] fetch_funding_rate — StandardError: network down.*symbol=ETHUSD/)
      )
      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "network down"),
        handled: true,
        context: hash_including("component" => "FundingMonitor", "symbol" => "ETHUSD")
      )
    end
  end
end
