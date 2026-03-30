require "rails_helper"

RSpec.describe Trading::Strategy::RegimeDetector do
  it "classifies trending" do
    regime = described_class.call(spread: 0.5, volatility: 10, imbalance: 0.7)

    expect(regime).to eq(:trending)
  end
end
