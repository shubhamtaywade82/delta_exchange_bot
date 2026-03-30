require "rails_helper"

RSpec.describe Trading::Learning::Reward do
  it "returns normalized net reward" do
    trade = Trade.new(realized_pnl: 100, fees: 10, holding_time_ms: 60_000, features: { "notional" => 1000 })

    reward = described_class.call(trade)

    expect(reward).to be_a(BigDecimal)
    expect(reward).to be < 0.1.to_d
  end
end
