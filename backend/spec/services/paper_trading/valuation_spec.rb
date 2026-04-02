# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::Valuation do
  describe ".from_delta_product" do
    it "uses contract_lot_multiplier when present" do
      product = double(
        "product",
        contract_lot_multiplier: BigDecimal("0.002"),
        notional_type: nil
      )
      h = described_class.from_delta_product(product)
      expect(h[:risk_unit_per_contract]).to eq(BigDecimal("0.002"))
      expect(h[:valuation_strategy]).to eq(PaperTrading::Valuation::STRATEGY_LINEAR)
    end

    it "marks inverse notional strategy" do
      product = double(
        "product",
        contract_lot_multiplier: BigDecimal("1"),
        notional_type: "inverse"
      )
      h = described_class.from_delta_product(product)
      expect(h[:valuation_strategy]).to eq(PaperTrading::Valuation::STRATEGY_INVERSE)
    end
  end
end
