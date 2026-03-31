require "rails_helper"

RSpec.describe Trading::RiskManager do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:signal) do
    Trading::Events::SignalGenerated.new(
      symbol: "BTCUSD", side: "buy", entry_price: 50000.0,
      candle_timestamp: Time.current, strategy: "multi_timeframe", session_id: session.id
    )
  end

  it "passes when no positions are open and no daily losses" do
    expect { described_class.validate!(signal, session: session) }.not_to raise_error
  end

  it "raises RiskError when max concurrent positions reached" do
    5.times do |i|
      Position.create!(symbol: "SYM#{i}", side: "long", status: "filled",
                       size: 1.0, entry_price: 100.0, leverage: 10)
    end
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /max concurrent/)
  end

  it "raises RiskError when margin utilization exceeds 40%" do
    Position.create!(symbol: "ETHUSD", side: "long", status: "filled",
                     size: 1.0, entry_price: 100.0, leverage: 10, margin: 420.0)
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /margin/)
  end

  it "raises RiskError when daily loss cap exceeded" do
    Trade.create!(symbol: "BTCUSD", side: "long", size: 1.0,
                  strategy: "multi_timeframe", regime: "mean_reversion",
                  entry_price: 50000.0, exit_price: 49000.0,
                  pnl_usd: -60.0, closed_at: Time.current)
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /daily loss/)
  end

  it "skips validation when paper risk override is active" do
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
    Setting.create!(key: Trading::PaperRiskOverride::KEY, value: "true", value_type: "boolean")
    Trade.create!(symbol: "BTCUSD", side: "long", size: 1.0,
                  strategy: "multi_timeframe", regime: "mean_reversion",
                  entry_price: 50000.0, exit_price: 49000.0,
                  pnl_usd: -60.0, closed_at: Time.current)
    expect { described_class.validate!(signal, session: session) }.not_to raise_error
  end
end
