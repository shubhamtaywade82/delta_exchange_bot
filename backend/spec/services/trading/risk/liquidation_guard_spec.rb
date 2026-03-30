require "rails_helper"

RSpec.describe Trading::Risk::LiquidationGuard do
  it "returns liquidation when margin ratio exceeds 1" do
    position = Position.new(size: 1, leverage: 500)

    expect(described_class.call(position: position, mark_price: 100)).to eq(:liquidation)
  end

  it "returns safe for empty position" do
    position = Position.new(size: 0)

    expect(described_class.call(position: position, mark_price: 100)).to eq(:safe)
  end
end
