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
      # risk basis $10k (portfolio balance); risk 1.5%; stop distance 50; rpc = 50 * 0.001 = 0.05 → 3000 contracts
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

    it "rejects sizing when portfolio available_balance is not positive" do
      session.portfolio.update!(available_balance: -100.0, balance: 75.0, used_margin: 9000.0)
      insolvent = SignalStub.new(
        symbol: "BTCUSD",
        side: :long,
        entry_price: 3000.0,
        candle_timestamp: 1,
        strategy: "mtf",
        stop_price: 2950.0
      )
      expect {
        described_class.build(insolvent, session: session, position: position)
      }.to raise_error(Trading::OrderBuilder::SizingError, /margin or product limit/)
    end

    it "caps size by portfolio available_balance (margin budget in USD)" do
      session.portfolio.update!(available_balance: 12.0, balance: 10_000, used_margin: 9_988)
      capped = SignalStub.new(
        symbol: "BTCUSD",
        side: :long,
        entry_price: 3000.0,
        candle_timestamp: 1,
        strategy: "mtf",
        stop_price: 2950.0
      )
      order = described_class.build(capped, session: session, position: position)
      # qty_risk = 3000; qty_margin = floor(12 * 0.98 * 10 / (0.001 * 3000)) = floor(39.2) = 39
      expect(order[:size]).to eq(39)
    end

    it "treats trail config as fractional when value is at most 1" do
      allow(Trading::RuntimeConfig).to receive(:fetch_float)
        .with("risk.trail_pct_for_sizing", default: 1.5, env_key: "RISK_TRAIL_PCT_FOR_SIZING")
        .and_return(0.015)
      no_stop = SignalStub.new(
        symbol: "BTCUSD",
        side: :long,
        entry_price: 3000.0,
        candle_timestamp: 1,
        strategy: "mtf"
      )
      order_fraction = described_class.build(no_stop, session: session, position: position)

      allow(Trading::RuntimeConfig).to receive(:fetch_float)
        .with("risk.trail_pct_for_sizing", default: 1.5, env_key: "RISK_TRAIL_PCT_FOR_SIZING")
        .and_return(1.5)
      order_points = described_class.build(no_stop, session: session, position: position)

      expect(order_fraction[:size]).to eq(order_points[:size])
    end

    it "sizes from portfolio balance when it exceeds session capital" do
      session.portfolio.update!(balance: 20_000, available_balance: 20_000, used_margin: 0)
      session.update!(capital: 10_000)
      same_as_explicit = SignalStub.new(
        symbol: "BTCUSD",
        side: :long,
        entry_price: 3000.0,
        candle_timestamp: 1,
        strategy: "mtf",
        stop_price: 2950.0
      )
      order = described_class.build(same_as_explicit, session: session, position: position)
      expect(order[:size]).to eq(6000)
    end

    it "caps size by PaperProductSnapshot position_size_limit when present" do
      create(:paper_product_snapshot, symbol: "BTCUSD", product_id: 99_001, position_size_limit: 50)
      limited = SignalStub.new(
        symbol: "BTCUSD",
        side: :long,
        entry_price: 3000.0,
        candle_timestamp: 1,
        strategy: "mtf",
        stop_price: 2950.0
      )
      order = described_class.build(limited, session: session, position: position)
      expect(order[:size]).to eq(50)
    end
  end
end
