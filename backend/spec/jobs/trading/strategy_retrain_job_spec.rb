require "rails_helper"

RSpec.describe Trading::StrategyRetrainJob, type: :job do
  it "writes grouped summary to cache" do
    Trade.create!(symbol: "BTCUSD", side: "buy", size: 1, entry_price: 100, exit_price: 101, realized_edge: 1.2, regime: "trending", strategy: "scalping")

    described_class.perform_now

    expect(Rails.cache.read("adaptive:training_summary")).to be_present
  end
end
