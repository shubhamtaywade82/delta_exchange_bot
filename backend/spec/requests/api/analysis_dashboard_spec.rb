# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::AnalysisDashboard", type: :request do
  describe "GET /api/analysis_dashboard" do
    it "returns stored JSON payload" do
      smc_confluence_last_bar = {
        "bar_index" => 99,
        "long_score" => 3,
        "short_score" => 1,
        "structure_bias" => "bullish",
        "long_signal" => false,
        "short_signal" => false
      }
      smc_confluence_mtf = {
        "kind" => "smc_confluence_mtf",
        "symbol" => "BTCUSD",
        "timeframes" => {
          "5m" => {
            "resolution" => "5m",
            "confluence" => smc_confluence_last_bar
          }
        },
        "alignment" => {
          "long_score" => { "5m" => 3, "15m" => 2, "1h" => 1 },
          "short_score" => { "5m" => 1, "15m" => 0, "1h" => 0 },
          "structure_bias" => { "5m" => "bullish", "15m" => "bullish", "1h" => "bearish" },
          "long_signal" => { "5m" => false, "15m" => false, "1h" => false },
          "short_signal" => { "5m" => false, "15m" => false, "1h" => false },
          "choch_bull" => { "5m" => false, "15m" => false, "1h" => false },
          "choch_bear" => { "5m" => false, "15m" => false, "1h" => false }
        }
      }
      payload = {
        "updated_at" => Time.current.iso8601,
        "symbols" => [
          {
            "symbol" => "BTCUSD",
            "error" => nil,
            "smc" => { "bos" => { "direction" => "bullish" } },
            "smc_confluence_mtf" => smc_confluence_mtf,
            "smc_by_timeframe" => {
              "5m" => { "resolution" => "5m", "smc_confluence" => smc_confluence_last_bar }
            }
          }
        ],
        "meta" => { "source" => "test" }
      }
      allow(Trading::Analysis::Store).to receive(:read).and_return(payload)

      get "/api/analysis_dashboard"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["symbols"].size).to eq(1)
      sym = body["symbols"].first
      expect(sym["symbol"]).to eq("BTCUSD")
      expect(sym["smc_confluence_mtf"]["kind"]).to eq("smc_confluence_mtf")
      expect(sym["smc_confluence_mtf"]["alignment"]["long_score"]["5m"]).to eq(3)
      expect(sym["smc_by_timeframe"]["5m"]["smc_confluence"]["long_score"]).to eq(3)
    end
  end
end
