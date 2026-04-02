# spec/models/trading_session_spec.rb
require "rails_helper"

RSpec.describe TradingSession, type: :model do
  it "is valid with required attributes" do
    session = TradingSession.new(strategy: "multi_timeframe", status: "running", capital: 1000.0)
    expect(session).to be_valid
  end

  it "is invalid without strategy" do
    expect(TradingSession.new(status: "running")).not_to be_valid
  end

  it "defaults status to pending" do
    session = TradingSession.create!(strategy: "multi_timeframe", capital: 500.0)
    expect(session.status).to eq("pending")
  end

  it "#running? returns true when status is running" do
    session = TradingSession.new(status: "running")
    expect(session.running?).to be true
  end

  it "#running? returns false when status is stopped" do
    session = TradingSession.new(status: "stopped")
    expect(session.running?).to be false
  end

  it "still has a portfolio after capital update (regression: ensure_portfolio must run on update, not only create)" do
    session = TradingSession.create!(strategy: "dev_paper_unified", status: "running", capital: 1000.0)
    portfolio_id = session.portfolio_id
    expect(portfolio_id).to be_present

    session.update!(capital: 2000.0, leverage: 8)
    expect(session.reload.portfolio_id).to eq(portfolio_id)
  end
end
