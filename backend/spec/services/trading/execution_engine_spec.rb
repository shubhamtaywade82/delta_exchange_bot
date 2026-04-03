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
    key = Trading::IdempotencyGuard.key_for_signal(signal)
    Trading::IdempotencyGuard.release(key)
  end

  after do
    key = Trading::IdempotencyGuard.key_for_signal(signal)
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

  it "reports unexpected failures to the error reporter then re-raises" do
    allow(client).to receive(:place_order).and_raise(StandardError, "exchange unavailable")
    allow(Rails.logger).to receive(:error)
    allow(Rails.error).to receive(:report)

    expect {
      described_class.execute(signal, session: session, client: client)
    }.to raise_error(StandardError, "exchange unavailable")

    expect(Rails.error).to have_received(:report).with(
      an_object_having_attributes(message: "exchange unavailable"),
      handled: false,
      context: hash_including(
        "component" => "ExecutionEngine",
        "operation" => "execute",
        "symbol" => "BTCUSD",
        "order_persisted" => "true"
      )
    )
  end

  it "returns nil (skips) when idempotency key already acquired" do
    key = Trading::IdempotencyGuard.key_for_signal(signal)
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

  it "releases idempotency after risk rejection so the same candle is not stuck as duplicate" do
    allow(Trading::RiskManager).to receive(:validate!).and_raise(
      Trading::RiskManager::RiskError, "daily loss cap exceeded"
    )
    key = Trading::IdempotencyGuard.key_for_signal(signal)
    expect {
      described_class.execute(signal, session: session, client: client)
    }.to raise_error(Trading::RiskManager::RiskError)

    expect(Trading::IdempotencyGuard.acquire(key)).to eq(true)
  end

  it "does not evaluate portfolio guard when paper risk override is active" do
    allow(Trading::RiskManager).to receive(:validate!).and_return(true)
    allow(Trading::PaperRiskOverride).to receive(:active?).and_return(true)
    expect(Trading::Risk::PortfolioGuard).not_to receive(:call)
    described_class.execute(signal, session: session, client: client)
  end

  it "dedupes long and buy to the same idempotency key" do
    long_signal = Trading::Events::SignalGenerated.new(
      symbol: "BTCUSD",
      side: "long",
      entry_price: 50_000.0,
      candle_timestamp: signal.candle_timestamp,
      strategy: "multi_timeframe",
      session_id: session.id
    )
    key_long = Trading::IdempotencyGuard.key_for_signal(long_signal)
    key_buy = Trading::IdempotencyGuard.key_for_signal(signal)
    expect(key_long).to eq(key_buy)
  end

  context "when paper trading rejects orders that exceed available margin" do
    before do
      allow(Trading::PaperRiskOverride).to receive(:active?).and_return(false)
      allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
      allow(Trading::FillProcessor).to receive(:process)
      allow(Rails.cache).to receive(:read).and_wrap_original do |method, key, *rest|
        key.to_s == "ltp:BTCUSD" ? 50_000.0 : method.call(key, *rest)
      end
      session.portfolio.update!(balance: 100, available_balance: 100, used_margin: 0)
      allow(Trading::OrderBuilder).to receive(:build).and_wrap_original do |original, signal, session:, position:|
        original.call(signal, session: session, position: position).merge(size: 10_000)
      end
    end

    it "raises RiskError and does not persist an order" do
      expect do
        described_class.execute(signal, session: session, client: client)
      end.to raise_error(Trading::RiskManager::RiskError, /insufficient cash for margin/)
      expect(Order.count).to eq(0)
      expect(Trading::FillProcessor).not_to have_received(:process)
    end
  end

  context "when a closed position row already exists for the symbol" do
    let(:signal) do
      Trading::Events::SignalGenerated.new(
        symbol: "BTCUSD",
        side: "short",
        entry_price: 50_000.0,
        candle_timestamp: Time.current,
        strategy: "multi_timeframe",
        session_id: session.id
      )
    end

    before do
      Position.create!(
        portfolio: session.portfolio,
        symbol: "BTCUSD",
        side: "short",
        status: "closed",
        size: 1.0,
        entry_price: 51_000.0,
        leverage: 10
      )
      key = Trading::IdempotencyGuard.key_for_signal(signal)
      Trading::IdempotencyGuard.release(key)
    end

    after do
      key = Trading::IdempotencyGuard.key_for_signal(signal)
      Trading::IdempotencyGuard.release(key)
    end

    it "creates a new active position instead of attaching to the closed row" do
      closed = Position.find_by!(symbol: "BTCUSD", status: "closed")

      described_class.execute(signal, session: session, client: client)

      active = Position.active.find_by(symbol: "BTCUSD")
      expect(active).to be_present
      expect(active.id).not_to eq(closed.id)
      expect(closed.reload.status).to eq("closed")
    end
  end
end
