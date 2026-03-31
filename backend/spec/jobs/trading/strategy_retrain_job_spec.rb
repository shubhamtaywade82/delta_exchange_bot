require "rails_helper"

RSpec.describe Trading::StrategyRetrainJob, type: :job do
  it "writes grouped summary to cache" do
    Trade.create!(symbol: "BTCUSD", side: "buy", size: 1, entry_price: 100, exit_price: 101, realized_edge: 1.2, regime: "trending", strategy: "scalping")

    expect(Rails.cache).to receive(:write) do |key, summary, **kwargs|
      expect(key).to eq("adaptive:training_summary")
      expect(summary).to be_an(Array)
      expect(summary.first).to include(:regime, :strategy, :avg_realized_edge, :trades_count)
      expect(kwargs).to include(:expires_in)
    end

    described_class.perform_now
  end
end
