# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::ImpactModel do
  describe ".apply" do
    it "applies non-linear impact" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("PAPER_IMPACT_COEFF", "0.1").and_return("0.2")

      impacted = described_class.apply(price: BigDecimal("100"), quantity: 10, depth: 100, side: :buy)
      baseline = BigDecimal("100") + BigDecimal("0.2") * BigDecimal("0.1")**BigDecimal("1.5")

      expect(impacted).to eq(baseline)
    end
  end
end
