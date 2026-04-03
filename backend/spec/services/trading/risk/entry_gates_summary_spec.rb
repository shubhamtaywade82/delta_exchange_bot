# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Risk::EntryGatesSummary do
  let(:portfolio) do
    Trading::Risk::PortfolioSnapshot::Result.new(total_pnl: 0.to_d, total_exposure: 1.to_d)
  end

  it "reports daily loss gate when today’s closed trades breach the session cap" do
    session = create(:trading_session, capital: 120.0)
    travel_to Time.zone.parse("2026-04-01 12:00:00") do
      create(:trade,
             symbol: "BTCUSD",
             strategy: "multi_timeframe",
             regime: "trending",
             closed_at: Time.current,
             pnl_usd: -13.0)

      summary = described_class.call(session: session, portfolio: portfolio)

      expect(summary[:risk_gates][:daily_loss_cap][:blocks_new_entries]).to be true
      expect(summary[:blockers].pluck(:code)).to include("daily_loss_cap")
    end
  end

  it "includes no_running_session when session is nil" do
    summary = described_class.call(session: nil, portfolio: portfolio)

    expect(summary[:trading_session]).to be_nil
    expect(summary[:risk_gates]).to be_nil
    expect(summary[:blockers].pluck(:code)).to include("no_running_session")
  end

  it "sets auto_entry_allowed when paper override bypasses overridable blockers" do
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
    Setting.create!(key: Trading::PaperRiskOverride::KEY, value: "true", value_type: "boolean")
    session = create(:trading_session, capital: 120.0)
    travel_to Time.zone.parse("2026-04-02 12:00:00") do
      create(:trade,
             symbol: "BTCUSD",
             strategy: "multi_timeframe",
             regime: "trending",
             closed_at: Time.current,
             pnl_usd: -13.0)

      summary = described_class.call(session: session, portfolio: portfolio)

      expect(summary[:gates_would_block]).to be true
      expect(summary[:paper_risk_override_active]).to be true
      expect(summary[:auto_entry_allowed]).to be true
    end
  end

  it "does not auto-allow when no_running_session even with override" do
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
    Setting.create!(key: Trading::PaperRiskOverride::KEY, value: "true", value_type: "boolean")

    summary = described_class.call(session: nil, portfolio: portfolio)

    expect(summary[:auto_entry_allowed]).to be false
  end
end
