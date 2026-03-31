require "rails_helper"

RSpec.describe Trading::ExecutionEngine do
  let(:session) do
    TradingSession.create!(strategy: "multi_timeframe", status: "running",
                           capital: 1000.0, leverage: 10)
  end
  let(:client) { double("DeltaExchange::Client") }
  let(:signal) do
    Trading::Events::SignalGenerated.new(
      symbol:           "BTCUSD",
      side:             "buy",
      entry_price:      50000.0,
      candle_timestamp: Time.current,
      strategy:         "multi_timeframe",
      session_id:       session.id
    )
  end

  before do
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(false)
    allow(client).to receive(:place_order).and_return({ id: "EX-001", status: "open" })
    allow(Trading::RiskManager).to receive(:validate!).and_return(true)
    allow(Rails.cache).to receive(:fetch).with(/product_id:/, anything).and_return(84)
    allow(Trading::Risk::PositionLotSize).to receive(:from_exchange).and_return(0.001)
    allow(Trading::Risk::PositionLotSize).to receive(:multiplier_for).and_return(0.001)
    allow(Trading::RuntimeConfig).to receive(:fetch_float).and_call_original
    allow(Trading::RuntimeConfig).to receive(:fetch_float)
      .with("risk.trail_pct_for_sizing", default: 1.5, env_key: "RISK_TRAIL_PCT_FOR_SIZING")
      .and_return(1.5)
    # Clean up idempotency keys after each test
    key = Trading::IdempotencyGuard.key(
      symbol: "BTCUSD", side: "buy", timestamp: signal.candle_timestamp.to_i
    )
    Trading::IdempotencyGuard.release(key)
  end

  after do
    key = Trading::IdempotencyGuard.key(
      symbol: "BTCUSD", side: "buy", timestamp: signal.candle_timestamp.to_i
    )
    Trading::IdempotencyGuard.release(key)
  end

  it "creates an Order record" do
    expect {
      described_class.execute(signal, session: session, client: client)
    }.to change(Order, :count).by(1)
  end

  it "calls client.place_order" do
    described_class.execute(signal, session: session, client: client)
    expect(client).to have_received(:place_order)
  end

  it "stores exchange_order_id on the order" do
    described_class.execute(signal, session: session, client: client)
    expect(Order.last.exchange_order_id).to eq("EX-001")
  end

  it "returns nil (skips) when idempotency key already acquired" do
    key = Trading::IdempotencyGuard.key(
      symbol: signal.symbol, side: signal.side, timestamp: signal.candle_timestamp.to_i
    )
    Trading::IdempotencyGuard.acquire(key)

    result = described_class.execute(signal, session: session, client: client)
    expect(result).to be_nil
    expect(Order.count).to eq(0)
  end

  it "raises and creates no order when risk validation fails" do
    allow(Trading::RiskManager).to receive(:validate!).and_raise(
      Trading::RiskManager::RiskError, "max positions"
    )
    expect {
      described_class.execute(signal, session: session, client: client)
    }.to raise_error(Trading::RiskManager::RiskError)
    expect(Order.count).to eq(0)
  end
end
