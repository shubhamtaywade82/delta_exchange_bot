require "rails_helper"

RSpec.describe Trading::Runner do
  let(:session) { TradingSession.create!(strategy: "mtf", status: "running", capital: 10_000, leverage: 10) }
  let(:client) { instance_double("DeltaExchange::Client") }
  let(:runner) { described_class.new(session_id: session.id, client: client) }

  describe "signal persistence lifecycle" do
    it "marks signal as executed on successful execution" do
      allow(Trading::ExecutionEngine).to receive(:execute).and_return(true)
      allow(Trading::EventBus).to receive(:publish)

      runner.send(
        :execute_signal,
        symbol: "BTCUSD",
        side: :buy,
        entry_price: 50_000.0,
        candle_timestamp: Time.now.to_i,
        strategy_name: "adaptive:scalping",
        source: "adaptive",
        context: { "decision" => "buy" }
      )

      signal = GeneratedSignal.order(:created_at).last
      expect(signal.status).to eq("executed")
      expect(signal.source).to eq("adaptive")
    end

    it "marks signal as rejected when risk manager blocks execution" do
      allow(Trading::ExecutionEngine).to receive(:execute).and_raise(Trading::RiskManager::RiskError, "risk rejected")
      allow(Trading::EventBus).to receive(:publish)

      runner.send(
        :execute_signal,
        symbol: "ETHUSD",
        side: :sell,
        entry_price: 3_200.0,
        candle_timestamp: Time.now.to_i,
        strategy_name: "mtf",
        source: "mtf",
        context: {}
      )

      signal = GeneratedSignal.order(:created_at).last
      expect(signal.status).to eq("rejected")
      expect(signal.error_message).to include("risk rejected")
    end

    it "marks signal as skipped_duplicate when execution engine returns nil (idempotency)" do
      allow(Trading::ExecutionEngine).to receive(:execute).and_return(nil)
      allow(Trading::EventBus).to receive(:publish)

      runner.send(
        :execute_signal,
        symbol: "BTCUSD",
        side: :buy,
        entry_price: 50_000.0,
        candle_timestamp: Time.now.to_i,
        strategy_name: "mtf",
        source: "mtf",
        context: {}
      )

      signal = GeneratedSignal.order(:created_at).last
      expect(signal.status).to eq("skipped_duplicate")
      expect(signal.error_message).to include("idempotency")
    end

    it "marks signal as failed and re-raises when execution raises before outer loop swallows" do
      allow(Trading::EventBus).to receive(:publish)
      allow(Trading::ExecutionEngine).to receive(:execute).and_raise(StandardError, "execution boom")

      expect {
        runner.send(
          :execute_signal,
          symbol: "SOLUSD",
          side: :buy,
          entry_price: 100.0,
          candle_timestamp: Time.now.to_i,
          strategy_name: "mtf",
          source: "mtf",
          context: {}
        )
      }.to raise_error(StandardError, "execution boom")

      signal = GeneratedSignal.order(:created_at).last
      expect(signal.status).to eq("failed")
      expect(signal.error_message).to eq("execution boom")
    end
  end

  describe "hot-path error reporting" do
    it "reports swallowed errors from fetch_last_price" do
      market_data = instance_double("DeltaExchange::MarketData")
      allow(client).to receive(:market_data).and_return(market_data)
      allow(market_data).to receive(:ticker).and_raise(StandardError, "api down")
      allow(Rails.error).to receive(:report)

      price = runner.send(:fetch_last_price, "BTCUSD")

      expect(price).to be_nil
      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "api down"),
        handled: true,
        context: hash_including(
          "component" => "Runner",
          "operation" => "fetch_last_price",
          "symbol" => "BTCUSD"
        )
      )
    end
  end
end
