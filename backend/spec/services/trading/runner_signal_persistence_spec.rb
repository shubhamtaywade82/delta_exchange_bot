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
  end
end
