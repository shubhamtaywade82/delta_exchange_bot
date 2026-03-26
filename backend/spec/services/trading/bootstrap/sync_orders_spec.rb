# spec/services/trading/bootstrap/sync_orders_spec.rb
require "rails_helper"

RSpec.describe Trading::Bootstrap::SyncOrders do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:client)  { double("DeltaExchange::Client") }

  before do
    allow(client).to receive(:get_open_orders).and_return([
      { id: "EX-001", symbol: "BTCUSD", side: "buy", size: 1.0,
        price: 50000.0, order_type: "limit_order", status: "open" }
    ])
  end

  it "marks stale local pending orders as cancelled" do
    stale = Order.create!(
      trading_session: session, symbol: "BTCUSD", side: "buy",
      size: 1.0, price: 49000.0, order_type: "limit_order",
      status: "pending", idempotency_key: "old-key-1",
      exchange_order_id: "EX-STALE"
    )
    described_class.call(client: client, session: session)
    expect(stale.reload.status).to eq("cancelled")
  end
end
