require "rails_helper"

RSpec.describe "Api::Signals", type: :request do
  it "returns recent generated signals" do
    session = TradingSession.create!(strategy: "mtf", status: "running", capital: 10_000, leverage: 10)
    GeneratedSignal.create!(
      trading_session: session,
      symbol: "BTCUSD",
      side: "buy",
      entry_price: 50_000.0,
      candle_timestamp: Time.now.to_i,
      strategy: "mtf",
      source: "mtf",
      status: "generated",
      context: {}
    )

    get "/api/signals"

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload).to be_an(Array)
    expect(payload.first["symbol"]).to eq("BTCUSD")
  end
end
