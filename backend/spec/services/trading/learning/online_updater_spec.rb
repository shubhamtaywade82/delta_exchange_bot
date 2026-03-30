require "rails_helper"

RSpec.describe Trading::Learning::OnlineUpdater do
  it "creates strategy params and updates bounded values" do
    allow(Trading::Learning::OnlineUpdater).to receive(:freeze_learning?).and_return(false)

    trade = Trade.create!(
      symbol: "BTCUSD",
      side: "buy",
      size: 1,
      entry_price: 100,
      exit_price: 110,
      strategy: "scalping",
      regime: "trending",
      realized_pnl: 10,
      fees: 1,
      holding_time_ms: 1_000,
      features: { "notional" => 1000 }
    )

    params = described_class.update!(trade)

    expect(params).to be_present
    expect(params.aggression.to_d).to be_between(0.1.to_d, 2.0.to_d)
    expect(params.risk_multiplier.to_d).to be_between(0.1.to_d, 2.0.to_d)
  end
end
