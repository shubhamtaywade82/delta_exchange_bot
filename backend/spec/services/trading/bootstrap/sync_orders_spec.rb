# spec/services/trading/bootstrap/sync_orders_spec.rb
require "rails_helper"

RSpec.describe Trading::Bootstrap::SyncOrders do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:client)  { double("DeltaExchange::Client") }

  before do
    allow(client).to receive(:get_open_orders).and_return([
      { id: "EX-001", symbol: "BTCUSD", side: "buy", size: 1.0,
        price: 50_000.0, order_type: "limit_order", status: "open" }
    ])
  end

  it "marks stale local submitted orders as cancelled" do
    stale = Order.create!(
      trading_session: session,
      symbol: "BTCUSD",
      side: "buy",
      size: 1.0,
      price: 49_000.0,
      order_type: "limit_order",
      status: "submitted",
      idempotency_key: "old-key-1",
      client_order_id: SecureRandom.uuid,
      exchange_order_id: "EX-STALE"
    )

    described_class.call(client: client, session: session)

    expect(stale.reload.status).to eq("cancelled")
  end

  it "reports a warning and uses empty open ids when fetch fails" do
    allow(client).to receive(:get_open_orders).and_raise(StandardError, "timeout")
    allow(Rails.logger).to receive(:warn)
    allow(Rails.error).to receive(:report)

    described_class.call(client: client, session: session)

    expect(Rails.error).to have_received(:report).with(
      an_object_having_attributes(message: "timeout"),
      handled: true,
      context: hash_including(
        "component" => "Bootstrap::SyncOrders",
        "operation" => "fetch_open_exchange_order_ids",
        "session_id" => session.id.to_s
      )
    )
  end
end
