require "rails_helper"

RSpec.describe Trading::Risk::MarginCalculator do
  it "computes margin fields" do
    position = Position.new(size: 2, leverage: 10)

    result = described_class.call(position: position, mark_price: 100)

    expect(result.position_value.to_d).to eq(200.to_d)
    expect(result.initial_margin.to_d).to eq(20.to_d)
    expect(result.maintenance_margin).to be > 0
    expect(result.margin_ratio).to be > 0
  end

  it "scales exposure by persisted contract_value (lot multiplier)" do
    position = Position.new(size: 2, leverage: 10, contract_value: 0.5)

    result = described_class.call(position: position, mark_price: 100)

    expect(result.position_value.to_d).to eq(100.to_d)
    expect(result.initial_margin.to_d).to eq(10.to_d)
  end
end
