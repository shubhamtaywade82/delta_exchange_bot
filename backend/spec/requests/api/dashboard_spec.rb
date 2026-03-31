require "rails_helper"

RSpec.describe "Api::Dashboard", type: :request do
  describe "GET /api/dashboard" do
    let(:entry_price_corrector) { instance_double(Bot::Execution::EntryPriceCorrector) }

    before do
      allow(Trading::Risk::PortfolioSnapshot).to receive(:current).and_return(
        double("PortfolioSnapshot", total_pnl: 0.0)
      )
      allow(Bot::Execution::IncidentStore).to receive(:latest).and_return(
        {
          "category" => "auth_whitelist",
          "message" => "{\"code\"=>\"ip_not_whitelisted_for_api_key\"}",
          "details" => { "broker_code" => "ip_not_whitelisted_for_api_key" }
        }
      )
      allow(Bot::Execution::IncidentStore).to receive(:recent).and_return([])
      allow(Bot::Execution::EntryPriceCorrector).to receive(:new).and_return(entry_price_corrector)
      allow(entry_price_corrector).to receive(:corrected_entry_for) { |position| position.entry_price.to_f }
      SymbolConfig.create!(symbol: "BTCUSD", leverage: 10, enabled: true)
    end

    it "returns execution health fields in payload" do
      get "/api/dashboard"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["execution_health"]).to include(
        "healthy" => false,
        "category" => "auth_whitelist",
        "last_broker_error_code" => "ip_not_whitelisted_for_api_key"
      )
    end

    it "includes unrealized_pnl_inr and unrealized_pnl_pct aligned with cached LTP" do
      create(:position,
             symbol: "BTCUSD",
             side: "short",
             status: "filled",
             entry_price: 100.0,
             size: 1.0,
             leverage: 10,
             margin: 10.0)
      Rails.cache.write("ltp:BTCUSD", 99.0)
      allow(Redis).to receive(:new).and_return(instance_double(Redis, get: nil))

      get "/api/dashboard"

      expect(response).to have_http_status(:ok)
      row = JSON.parse(response.body)["positions"].first
      expect(row["unrealized_pnl"]).to eq(1.0)
      expect(row["unrealized_pnl_inr"]).to eq(85)
      expect(row["unrealized_pnl_pct"]).to eq(10.0)
    end

    it "uses computed initial margin for ROE% when persisted margin is wrong scale" do
      create(:position,
             symbol: "BTCUSD",
             side: "short",
             status: "filled",
             entry_price: 67_017.0,
             size: 10.0,
             leverage: 10,
             margin: 67.0,
             contract_value: nil)
      Rails.cache.write("ltp:BTCUSD", 66_955.0)
      allow(Redis).to receive(:new).and_return(instance_double(Redis, get: nil))

      get "/api/dashboard"

      row = JSON.parse(response.body)["positions"].first
      expect(row["unrealized_pnl"]).to eq(620.0)
      expected_pct = ((620.0 / 67_017.0) * 100).round(2)
      expect(row["unrealized_pnl_pct"]).to eq(expected_pct)
      expect(row["unrealized_pnl_pct"]).to be < 2.0
    end

    it "keeps ROE% aligned with unrealized_pnl when contract_value is fractional" do
      create(:position,
             symbol: "BTCUSD",
             side: "short",
             status: "filled",
             entry_price: 67_017.0,
             size: 10.0,
             leverage: 10,
             margin: 67.0,
             contract_value: 0.001)
      Rails.cache.write("ltp:BTCUSD", 66_816.9)
      allow(Redis).to receive(:new).and_return(instance_double(Redis, get: nil))

      get "/api/dashboard"

      row = JSON.parse(response.body)["positions"].first
      expect(row["unrealized_pnl"]).to eq(2000.1)
      expect(row["unrealized_pnl_pct"]).to eq(2.98)
    end

    it "uses OHLCV-corrected entry when provided" do
      position = create(:position,
                        symbol: "BTCUSD",
                        side: "short",
                        status: "filled",
                        entry_price: 67_016.988,
                        size: 10.0,
                        leverage: 10)
      allow(entry_price_corrector).to receive(:corrected_entry_for).with(position).and_return(66_950.0)
      Rails.cache.write("ltp:BTCUSD", 66_777.54)
      allow(Redis).to receive(:new).and_return(instance_double(Redis, get: nil))

      get "/api/dashboard"

      row = JSON.parse(response.body)["positions"].first
      expect(row["entry_price"]).to eq(66_950.0)
      expect(row["unrealized_pnl"]).to eq(1724.6)
    end
  end
end
