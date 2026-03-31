require "rails_helper"

RSpec.describe "Api::Dashboard", type: :request do
  describe "GET /api/dashboard" do
    around do |example|
      previous_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = previous_cache
    end

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
      expect(row["unrealized_pnl"]).to eq(2.0)
      expect(row["unrealized_pnl_pct"]).to eq(2.98)
    end

    it "lists only broker-settled trades with a symbol and supports day filter" do
      allow(Redis).to receive(:new).and_return(instance_double(Redis, get: nil))
      day = Date.new(2026, 3, 31)
      create(:trade, symbol: "ETHUSD", side: "long", closed_at: day.in_time_zone.change(hour: 12),
             strategy: "multi_timeframe", regime: "trending", pnl_usd: 1.0)
      create(:trade, symbol: "BTCUSD", side: "long", closed_at: (day - 1).in_time_zone.change(hour: 12),
             strategy: "multi_timeframe", regime: "trending", pnl_usd: 1.0)
      create(:trade, symbol: nil, side: nil, closed_at: day.in_time_zone.change(hour: 10),
             strategy: "learn", regime: "explore", pnl_usd: 0.0)

      get "/api/dashboard", params: { trades_day: "2026-03-31" }

      body = JSON.parse(response.body)
      expect(body["trades"].map { |t| t["symbol"] }).to eq(["ETHUSD"])
      expect(body["trades_meta"]["total_count"]).to eq(1)
      expect(body["trades_meta"]["day"]).to eq("2026-03-31")
    end

    it "defaults trade history to the current day when trades_day is omitted" do
      allow(Redis).to receive(:new).and_return(instance_double(Redis, get: nil))
      day = Date.new(2026, 3, 31)
      travel_to day.in_time_zone.change(hour: 12) do
        create(:trade, symbol: "ETHUSD", side: "long", closed_at: day.in_time_zone.change(hour: 8),
               strategy: "multi_timeframe", regime: "trending", pnl_usd: 1.0)
        create(:trade, symbol: "BTCUSD", side: "long", closed_at: (day - 1).in_time_zone.change(hour: 8),
               strategy: "multi_timeframe", regime: "trending", pnl_usd: 2.0)

        get "/api/dashboard"

        body = JSON.parse(response.body)
        expect(body["trades"].map { |t| t["symbol"] }).to eq(["ETHUSD"])
        expect(body["trades_meta"]["day"]).to eq("2026-03-31")
      end
    end

    it "shows stored entry_price from the position row (no OHLCV override)" do
      create(:position,
             symbol: "BTCUSD",
             side: "short",
             status: "filled",
             entry_price: 67_010.5,
             size: 10.0,
             leverage: 10,
             entry_time: 3.days.ago)
      Rails.cache.write("ltp:BTCUSD", 66_979.0)
      allow(Redis).to receive(:new).and_return(instance_double(Redis, get: nil))

      get "/api/dashboard"

      row = JSON.parse(response.body)["positions"].first
      expect(row["entry_price"]).to eq(67_010.5)
      expect(row["unrealized_pnl"]).to eq(315.0)
    end
  end
end
