# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::OrderBuilder do
  SignalStub = Struct.new(
    :symbol, :side, :entry_price, :candle_timestamp, :strategy, :stop_price,
    keyword_init: true
  )

  let(:session) { create(:trading_session, strategy: "mtf", capital: 10_000) }
  let(:position) do
    Position.create!(
      portfolio: session.portfolio,
      symbol: "BTCUSD",
      side: "long",
      status: "init",
      leverage: 10,
      contract_value: 0.001
    )
  end

  before do
    allow(Trading::Risk::PositionLotSize).to receive(:multiplier_for).and_return(0.001)
    allow(Trading::RuntimeConfig).to receive(:fetch_float).and_call_original
    allow(Trading::RuntimeConfig).to receive(:fetch_float)
      .with("risk.trail_pct_for_sizing", default: 1.5, env_key: "RISK_TRAIL_PCT_FOR_SIZING")
      .and_return(1.5)
  end

  describe ".build" do
    it "increases size for adaptive signals with higher risk multiplier" do
      adaptive_signal = SignalStub.new(
        symbol: "BTCUSD",
        side: :buy,
        entry_price: 1_000.0,
        candle_timestamp: 1_700_000_000,
        strategy: "adaptive:scalping"
      )
      classic_signal = SignalStub.new(
        symbol: "BTCUSD",
        side: :buy,
        entry_price: 1_000.0,
        candle_timestamp: 1_700_000_000,
        strategy: "mtf"
      )

      allow(Rails.cache).to receive(:read).with("adaptive:entry_context:BTCUSD").and_return(
        { "ai_config" => { "risk_multiplier" => 2.0 }, "bias" => 0.2 }
      )

      adaptive_order = described_class.build(adaptive_signal, session: session, position: position)
      classic_order = described_class.build(classic_signal, session: session, position: position)

      expect(adaptive_order[:size]).to be > classic_order[:size]
    end

    it "uses explicit stop_price when present" do
      with_stop = SignalStub.new(
        symbol: "BTCUSD",
        side: :long,
        entry_price: 3_000.0,
        candle_timestamp: 1_700_000_000,
        strategy: "mtf",
        stop_price: 2_950.0
      )
      # balance_inr = 10_000 * 85; risk 1.5% USD; stop distance 50; rpc = 50 * 0.001 = 0.05 → 3000 contracts
      order = described_class.build(with_stop, session: session, position: position)
      expect(order[:size]).to eq(3_000)
    end

    it "raises SizingError when risk budget yields zero contracts" do
      allow(Trading::Risk::PositionLotSize).to receive(:multiplier_for).and_return(1.0)
      tiny = SignalStub.new(
        symbol: "BTCUSD",
        side: :long,
        entry_price: 100_000.0,
        candle_timestamp: 1,
        strategy: "mtf",
        stop_price: 49_999.0
      )
      # Min risk ~0.5% of $10k = $50; stop distance 50_001 → rpc = 50.001 → floor(50/50.001) = 0
      expect {
        described_class.build(tiny, session: session, position: position)
      }.to raise_error(Trading::OrderBuilder::SizingError, /zero contracts/)
    end
  end
end
