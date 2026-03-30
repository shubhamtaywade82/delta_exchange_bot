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
      allow_any_instance_of(Trading::KillSwitch).to receive(:trigger!)
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
  end
end
