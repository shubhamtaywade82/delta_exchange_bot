require "rails_helper"

RSpec.describe Trading::Strategy::AiEdgeModel do
  it "falls back on parser error" do
    allow(Ai::OllamaClient).to receive(:ask).and_return("not-json")
    allow(Rails.error).to receive(:report)

    output = described_class.call(features: { spread: 1, imbalance: 0.1, volatility: 2, momentum: 0 }, regime: :trending)

    expect(output["strategy"]).to eq("scalping")
    expect(Rails.error).to have_received(:report).with(
      kind_of(StandardError),
      handled: true,
      context: hash_including("component" => "Strategy::AiEdgeModel", "operation" => "call", "regime" => "trending")
    )
  end
end
