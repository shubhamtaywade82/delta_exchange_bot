require "rails_helper"

RSpec.describe Trading::Risk::KillSwitch do
  it "halts when pnl breaches threshold" do
    portfolio = Trading::Risk::PortfolioSnapshot::Result.new(total_pnl: -20_000.to_d, total_exposure: 1.to_d)

    expect(described_class.call(portfolio: portfolio)).to eq(:halt_trading)
  end

  it "blocks when exposure breaches threshold" do
    portfolio = Trading::Risk::PortfolioSnapshot::Result.new(total_pnl: 100.to_d, total_exposure: 200_000.to_d)

    expect(described_class.call(portfolio: portfolio)).to eq(:block_new_trades)
  end
end
