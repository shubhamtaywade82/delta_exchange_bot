require "rails_helper"

RSpec.describe Trading::RiskManager do
  let(:session) { create(:trading_session, strategy: "multi_timeframe", capital: 1000.0) }
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
      Position.create!(portfolio: session.portfolio, symbol: "SYM#{i}", side: "long", status: "filled",
                       size: 1.0, entry_price: 100.0, leverage: 10)
    end
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /max concurrent/)
  end

  it "raises RiskError when margin utilization exceeds 40%" do
    Position.create!(portfolio: session.portfolio, symbol: "ETHUSD", side: "long", status: "filled",
                     size: 1.0, entry_price: 100.0, leverage: 10, margin: 420.0)
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /margin/)
  end

  it "raises RiskError when daily loss cap exceeded" do
    Trade.create!(portfolio: session.portfolio, symbol: "BTCUSD", side: "long", size: 1.0,
                  strategy: "multi_timeframe", regime: "mean_reversion",
                  entry_price: 50_000.0, exit_price: 49_000.0,
                  pnl_usd: -60.0, closed_at: Time.current)
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /daily loss/)
  end

  it "scales daily loss cap with portfolio balance when balance exceeds session capital" do
    session.portfolio.update!(balance: 2000, available_balance: 2000, used_margin: 0)
    session.update!(capital: 1000)
    Trade.create!(portfolio: session.portfolio, symbol: "BTCUSD", side: "long", size: 1.0,
                  strategy: "multi_timeframe", regime: "mean_reversion",
                  entry_price: 50_000.0, exit_price: 49_000.0,
                  pnl_usd: -60.0, closed_at: Time.current)
    expect { described_class.validate!(signal, session: session) }.not_to raise_error
  end

  it "uses portfolio balance for margin utilization denominator" do
    session.portfolio.update!(balance: 5000, available_balance: 5000, used_margin: 0)
    session.update!(capital: 1000)
    Position.create!(portfolio: session.portfolio, symbol: "ETHUSD", side: "long", status: "filled",
                     size: 1.0, entry_price: 100.0, leverage: 10, margin: 2100.0)
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /margin/)
  end

  it "skips validation when paper risk override is active" do
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
    Setting.create!(key: Trading::PaperRiskOverride::KEY, value: "true", value_type: "boolean")
    Trade.create!(portfolio: session.portfolio, symbol: "BTCUSD", side: "long", size: 1.0,
                  strategy: "multi_timeframe", regime: "mean_reversion",
                  entry_price: 50_000.0, exit_price: 49_000.0,
                  pnl_usd: -60.0, closed_at: Time.current)
    expect { described_class.validate!(signal, session: session) }.not_to raise_error
  end

  context "when risk.allow_pyramiding is false" do
    before do
      allow(Trading::RuntimeConfig).to receive(:fetch_boolean).and_wrap_original do |m, key, **kwargs|
        key == "risk.allow_pyramiding" ? false : m.call(key, **kwargs)
      end
    end

    it "raises when an active same-side position already exists for the symbol" do
      Position.create!(portfolio: session.portfolio, symbol: "BTCUSD", side: "long", status: "filled",
                       size: 1.0, entry_price: 50_000.0, leverage: 10)
      expect {
        described_class.validate!(signal, session: session)
      }.to raise_error(Trading::RiskManager::RiskError, /pyramiding disabled/)
    end

    it "does not raise when the open position is opposite side" do
      Position.create!(portfolio: session.portfolio, symbol: "BTCUSD", side: "short", status: "filled",
                       size: 1.0, entry_price: 50_000.0, leverage: 10)
      expect { described_class.validate!(signal, session: session) }.not_to raise_error
    end
  end

  context "when another session portfolio has heavy risk usage" do
    let(:other_session) { create(:trading_session, strategy: "multi_timeframe", capital: 1000.0) }

    it "does not count the other portfolio’s positions toward max concurrent" do
      5.times do |i|
        Position.create!(portfolio: other_session.portfolio, symbol: "OTH#{i}", side: "long", status: "filled",
                         size: 1.0, entry_price: 100.0, leverage: 10)
      end
      expect { described_class.validate!(signal, session: session) }.not_to raise_error
    end

    it "does not include the other portfolio’s margin in utilization" do
      Position.create!(portfolio: other_session.portfolio, symbol: "OTH0", side: "long", status: "filled",
                       size: 1.0, entry_price: 100.0, leverage: 10, margin: 10_000.0)
      expect { described_class.validate!(signal, session: session) }.not_to raise_error
    end

    it "does not apply the other portfolio’s realized losses to this session’s daily loss cap" do
      Trade.create!(portfolio: other_session.portfolio, symbol: "OTH0", side: "long", size: 1.0,
                    strategy: "multi_timeframe", regime: "mean_reversion",
                    entry_price: 100.0, exit_price: 1.0,
                    pnl_usd: -500.0, closed_at: Time.current)
      expect { described_class.validate!(signal, session: session) }.not_to raise_error
    end
  end
end
