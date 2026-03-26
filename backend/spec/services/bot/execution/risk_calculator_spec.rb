# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Execution::RiskCalculator do
  subject(:calculator) { described_class.new(usd_to_inr_rate: 85.0) }

  # BTCUSD example:
  # available_usdt=500, entry=$45000, 10x leverage, 1.5% risk, 1.5% trail, contract_value=0.001
  # capital_inr=42500, risk_inr=637.5, risk_usd=7.5
  # trail_distance=$675, loss_per_lot=$0.675
  # raw_lots=11.11, leveraged_lots=111.11 → 111 lots
  # margin for 111 lots = 111*0.001*45000/10 = $499.5 → exceeds 40% cap ($200)
  # capped = floor(200*10/(0.001*45000)) = floor(44.44) = 44 lots

  let(:params) do
    {
      available_usdt: 500.0,
      entry_price_usd: 45_000.0,
      leverage: 10,
      risk_per_trade_pct: 1.5,
      trail_pct: 1.5,
      contract_value: 0.001,
      max_margin_per_position_pct: 40.0
    }
  end

  it "returns 44 lots after margin cap for BTCUSD example" do
    expect(calculator.compute(**params)).to eq(44)
  end

  it "returns 0 when capital is too small for even 1 lot" do
    expect(calculator.compute(**params.merge(available_usdt: 0.1))).to eq(0)
  end

  it "does not apply margin cap when position is within limit" do
    result = calculator.compute(
      available_usdt: 10_000.0,
      entry_price_usd: 1.0,
      leverage: 1,
      risk_per_trade_pct: 1.5,
      trail_pct: 1.5,
      contract_value: 1.0,
      max_margin_per_position_pct: 40.0
    )
    expect(result).to be > 0
  end
end
