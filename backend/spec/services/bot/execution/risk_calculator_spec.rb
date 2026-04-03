# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Execution::RiskCalculator do
  subject(:calculator) { described_class.new(usd_to_inr_rate: 85.0) }

  # BTCUSD example:
  # available_usdt=500, entry=$45000, 10x leverage, 1.5% risk, 1.5% trail, contract_value=0.001
  # risk_usd = 500 × 1.5% = 7.5
  # trail_distance = 45000 × 1.5% = 675; risk_per_contract = 675 × 0.001 = 0.675
  # qty_risk = floor(7.5 / 0.675) = 11
  # margin_wallet = 500 × 40% = 200; qty_margin = floor(200×0.98×10 / (0.001×45000)) = 43
  # final = min(11, 43) = 11

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

  it "returns risk-limited contracts when risk binds before the margin wallet cap" do
    expect(calculator.compute(**params)).to eq(11)
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

  it "uses a higher stop for short side so risk_per_contract matches adverse move" do
    long_qty = calculator.compute(**params.merge(side: "buy"))
    short_qty = calculator.compute(**params.merge(side: "sell"))
    expect(long_qty).to eq(short_qty)
  end
end
