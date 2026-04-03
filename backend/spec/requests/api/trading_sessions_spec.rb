# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::TradingSessions", type: :request do
  before { allow(DeltaTradingJob).to receive(:perform_later) }

  describe "GET /api/trading_sessions" do
    it "returns list of sessions as JSON" do
      TradingSession.create!(strategy: "multi_timeframe", status: "stopped", capital: 1000.0)
      get "/api/trading_sessions"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
      expect(body.first["strategy"]).to eq("multi_timeframe")
    end

    it "returns pagination metadata when page is requested" do
      12.times do |i|
        TradingSession.create!(strategy: "multi_timeframe", status: "stopped", capital: 1000.0 + i)
      end

      get "/api/trading_sessions", params: { page: 1, per_page: 5 }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["sessions"].size).to eq(5)
      expect(body["meta"]["page"]).to eq(1)
      expect(body["meta"]["per_page"]).to eq(5)
      expect(body["meta"]["total"]).to eq(12)
    end
  end

  describe "POST /api/trading_sessions" do
    let(:valid_params) { { strategy: "multi_timeframe", capital: 1000.0, leverage: 10 } }

    it "creates a running session and enqueues DeltaTradingJob" do
      expect { post "/api/trading_sessions", params: valid_params }
        .to change(TradingSession, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["status"]).to eq("running")
      expect(DeltaTradingJob).to have_received(:perform_later)
    end

    it "accepts nested trading_session parameters" do
      post "/api/trading_sessions",
           params: { trading_session: { strategy: "multi_timeframe", capital: 500, leverage: 5 } }
      expect(response).to have_http_status(:created)
      expect(TradingSession.order(:id).last.capital).to eq(500)
    end

    it "does not apply unpermitted mass-assignment keys" do
      post "/api/trading_sessions",
           params: valid_params.merge(status: "crashed", portfolio_id: 9_999_999)
      created = TradingSession.order(:id).last
      expect(created.status).to eq("running")
      expect(created.portfolio_id).not_to eq(9_999_999)
    end

    it "returns 422 when strategy is missing" do
      post "/api/trading_sessions", params: { capital: 1000.0 }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/trading_sessions/:id" do
    let!(:session) do
      TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0)
    end

    before do
      allow_any_instance_of(Trading::EmergencyShutdown).to receive(:trigger!)
      stub_const("ENV", ENV.to_hash.merge("DELTA_API_KEY" => "test", "DELTA_API_SECRET" => "test"))
      allow(DeltaExchange::Client).to receive(:new).and_return(double("client"))
    end

    it "stops the session" do
      delete "/api/trading_sessions/#{session.id}"
      expect(response).to have_http_status(:ok)
      expect(session.reload.status).to eq("stopped")
    end

    it "returns 404 for unknown session" do
      delete "/api/trading_sessions/999999"
      expect(response).to have_http_status(:not_found)
    end

    it "returns ok when Delta credentials are missing" do
      stub_const("ENV", ENV.to_hash.except("DELTA_API_KEY", "DELTA_API_SECRET"))
      allow(Trading::EmergencyShutdown).to receive(:call)

      delete "/api/trading_sessions/#{session.id}"

      expect(response).to have_http_status(:ok)
      expect(Trading::EmergencyShutdown).not_to have_received(:call)
    end

    it "returns ok when emergency shutdown raises" do
      allow(Trading::EmergencyShutdown).to receive(:call).and_raise(StandardError, "delta unavailable")

      delete "/api/trading_sessions/#{session.id}"

      expect(response).to have_http_status(:ok)
      expect(session.reload.status).to eq("stopped")
    end
  end
end
