# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::AnalysisDashboard", type: :request do
  describe "GET /api/analysis_dashboard" do
    it "returns stored JSON payload" do
      payload = {
        "updated_at" => Time.current.iso8601,
        "symbols" => [
          { "symbol" => "BTCUSD", "error" => nil, "smc" => { "bos" => { "direction" => "bullish" } } }
        ],
        "meta" => { "source" => "test" }
      }
      allow(Trading::Analysis::Store).to receive(:read).and_return(payload)

      get "/api/analysis_dashboard"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["symbols"].size).to eq(1)
      expect(body["symbols"].first["symbol"]).to eq("BTCUSD")
    end
  end
end
