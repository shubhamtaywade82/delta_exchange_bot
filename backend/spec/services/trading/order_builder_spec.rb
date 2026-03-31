require "rails_helper"

RSpec.describe Trading::OrderBuilder do
  SignalStub = Struct.new(:symbol, :side, :entry_price, :candle_timestamp, :strategy, keyword_init: true)

  let(:session) { TradingSession.create!(strategy: "mtf", status: "running", capital: 10_000, leverage: 10) }
  let(:position) { Position.create!(symbol: "BTCUSD", side: "long", status: "init") }

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
  end
end
