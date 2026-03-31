require "rails_helper"

RSpec.describe Bot::Preflight::ExchangeAccessCheck do
  describe ".call" do
    it "returns healthy when wallet balance endpoint is reachable" do
      allow(DeltaExchange::Models::WalletBalance).to receive(:find_by_asset).with("USD").and_return(double("wallet"))

      result = described_class.call

      expect(result[:healthy]).to eq(true)
      expect(result[:category]).to eq("ok")
    end

    it "classifies whitelist failures from broker payload" do
      allow(DeltaExchange::Models::WalletBalance).to receive(:find_by_asset).with("USD")
        .and_raise(StandardError.new('{"code"=>"ip_not_whitelisted_for_api_key"}'))

      result = described_class.call

      expect(result[:healthy]).to eq(false)
      expect(result[:category]).to eq("auth_whitelist")
      expect(result[:broker_code]).to eq("ip_not_whitelisted_for_api_key")
    end
  end
end
