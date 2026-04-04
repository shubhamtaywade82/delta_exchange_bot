# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::FreshStart do
  let(:stdout) { StringIO.new }
  let(:redis_double) do
    instance_double(Redis).tap do |r|
      allow(r).to receive(:del)
      allow(r).to receive(:scan_each).and_yield("delta:order:BTCUSD:buy:123")
    end
  end

  before do
    allow(Redis).to receive(:current).and_return(redis_double)
    allow(Rails.cache).to receive(:clear)
  end

  it "aborts unless CONFIRM is YES" do
    expect {
      described_class.call!(confirm: "no", stdout: stdout)
    }.to raise_error(described_class::AbortError, /CONFIRM=YES/)
  end

  it "continues when a documented Redis key delete fails and reports" do
    allow(redis_double).to receive(:del) do |key|
      raise Redis::BaseError, "redis down" if key == described_class::REDIS_TRADING_DOCUMENTED_KEYS.first
    end
    allow(Rails.error).to receive(:report)

    described_class.call!(confirm: "YES", stdout: stdout)

    expect(Rails.error).to have_received(:report).with(
      instance_of(Redis::BaseError),
      handled: true,
      context: hash_including("component" => "FreshStart", "operation" => "flush_redis_trading_keys!")
    )
    expect(stdout.string).to include("[fresh_start] Redis DEL")
  end

  it "removes trades, orders chain, signals, positions, and strategy_params" do
    trade = create(:trade)
    portfolio = Portfolio.create!(balance: 1, available_balance: 1, used_margin: 0)
    session = TradingSession.create!(
      strategy: "multi_timeframe",
      status: "running",
      capital: 1000,
      portfolio: portfolio
    )
    position = Position.create!(
      symbol: "BTCUSD",
      side: "long",
      status: "filled",
      size: 1,
      entry_price: 50_000,
      leverage: 10,
      portfolio: portfolio
    )
    order = Order.create!(
      portfolio: portfolio,
      trading_session: session,
      position: position,
      symbol: "BTCUSD",
      side: "buy",
      size: 1,
      price: 50_000,
      order_type: "limit_order",
      status: "filled",
      idempotency_key: "fresh-start-spec-order",
      client_order_id: "cid-fresh-start"
    )
    Fill.create!(
      order: order,
      exchange_fill_id: "fill-fresh-start-1",
      filled_at: Time.current,
      quantity: 1,
      price: 50_000
    )
    PortfolioLedgerEntry.create!(
      portfolio: portfolio,
      fill: Fill.find_by!(exchange_fill_id: "fill-fresh-start-1"),
      balance_delta: 0,
      realized_pnl_delta: 0
    )
    GeneratedSignal.create!(
      trading_session: session,
      symbol: "BTCUSD",
      side: "buy",
      entry_price: 50_000,
      candle_timestamp: Time.current.to_i,
      strategy: "multi_timeframe",
      source: "mtf",
      status: "generated"
    )
    StrategyParam.create!(strategy: "scalping", regime: "trending", aggression: 0.5, risk_multiplier: 1.0)

    described_class.call!(confirm: "YES", stdout: stdout)

    expect(Trade.find_by(id: trade.id)).to be_nil
    expect(Order.count).to eq(0)
    expect(Fill.count).to eq(0)
    expect(PortfolioLedgerEntry.count).to eq(0)
    expect(Position.count).to eq(0)
    expect(GeneratedSignal.count).to eq(0)
    expect(StrategyParam.count).to eq(0)
    expect(Rails.cache).to have_received(:clear)
  end
end
