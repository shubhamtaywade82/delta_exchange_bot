# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Execution::OrderManager do
  let(:product_cache) do
    double("ProductCache",
      product_id_for: 1,
      contract_value_for: 0.001
    )
  end

  let(:position_tracker) { Bot::Execution::PositionTracker.new }
  let(:risk_calculator)  { double("RiskCalculator", compute: 44) }
  let(:capital_manager)  { double("CapitalManager", available_usdt: 500.0, usd_to_inr_rate: 85.0) }
  let(:logger)           { double("Logger", info: nil, warn: nil, error: nil) }
  let(:notifier)         { double("TelegramNotifier", send_message: nil) }

  let(:signal) do
    Bot::Strategy::Signal.new(
      symbol: "BTCUSD", side: :long, entry_price: 45_000.0, candle_ts: 1_000_000
    )
  end

  subject(:manager) do
    described_class.new(
      config: double(
        dry_run?: true, testnet?: false, live?: false,
        risk_per_trade_pct: 1.5, trailing_stop_pct: 1.5,
        max_margin_per_position_pct: 40.0, leverage_for: 10
      ),
      product_cache: product_cache,
      position_tracker: position_tracker,
      risk_calculator: risk_calculator,
      capital_manager: capital_manager,
      logger: logger,
      notifier: notifier
    )
  end

  describe "#execute_signal" do
    it "records position in tracker on dry-run" do
      manager.execute_signal(signal)
      expect(position_tracker.open?("BTCUSD")).to be(true)
    end

    it "does not call Order.create in dry-run mode" do
      expect(DeltaExchange::Models::Order).not_to receive(:create)
      manager.execute_signal(signal)
    end

    it "logs and returns nil when lots == 0" do
      allow(risk_calculator).to receive(:compute).and_return(0)
      expect(logger).to receive(:warn).with("skip_insufficient_capital", anything)
      expect(manager.execute_signal(signal)).to be_nil
    end

    it "skips when position already open for symbol" do
      manager.execute_signal(signal)
      expect(logger).to receive(:warn).with("skip_position_exists", anything)
      manager.execute_signal(signal)
    end
  end

  describe "#close_position" do
    before { manager.execute_signal(signal) }

    it "removes position from tracker in dry-run" do
      manager.close_position("BTCUSD", exit_price: 45_500.0, reason: :trail_stop)
      expect(position_tracker.open?("BTCUSD")).to be(false)
    end

    it "does not call Order.create in dry-run mode" do
      expect(DeltaExchange::Models::Order).not_to receive(:create)
      manager.close_position("BTCUSD", exit_price: 45_500.0, reason: :trail_stop)
    end

    it "sends Telegram notification including USD and INR PnL" do
      expect(notifier).to receive(:send_message).with(
        a_string_including("BTCUSD").and(a_string_including("$")).and(a_string_including("₹"))
      )
      manager.close_position("BTCUSD", exit_price: 45_500.0, reason: :trail_stop)
    end

    it "returns nil without error when symbol has no open position" do
      expect(manager.close_position("NONEXISTENT", exit_price: 100.0, reason: :trail_stop)).to be_nil
    end
  end
end
