# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Paper::CapitalAllocator do
  let(:risk_unit) { BigDecimal("1") }

  describe "#call" do
    it "sizes long quantity from risk budget and per-unit risk" do
      allocator = described_class.new(
        equity: BigDecimal("1000"),
        risk_pct: BigDecimal("0.01"),
        risk_unit_value: risk_unit
      )
      alloc = allocator.call(side: :long, entry_price: BigDecimal("100"), stop_price: BigDecimal("98"))
      expect(alloc.quantity).to eq(5)
      expect(alloc.valid?).to be true
      expect(alloc.notional).to eq(BigDecimal("100") * 5 * risk_unit)
    end

    it "returns invalid allocation when quantity rounds down to zero" do
      allocator = described_class.new(
        equity: BigDecimal("100"),
        risk_pct: BigDecimal("0.001"),
        risk_unit_value: risk_unit
      )
      alloc = allocator.call(side: :short, entry_price: BigDecimal("50000"), stop_price: BigDecimal("51000"))
      expect(alloc.quantity).to eq(0)
      expect(alloc.valid?).to be false
    end

    it "raises when per-unit risk is zero" do
      allocator = described_class.new(equity: "1000", risk_pct: "0.01", risk_unit_value: risk_unit)
      expect do
        allocator.call(side: :long, entry_price: "100", stop_price: "100")
      end.to raise_error(ArgumentError, /per_unit_risk/)
    end

    it "computes short target below entry" do
      allocator = described_class.new(
        equity: BigDecimal("50000"),
        risk_pct: BigDecimal("0.02"),
        target_profit_pct: BigDecimal("0.10"),
        risk_unit_value: risk_unit
      )
      alloc = allocator.call(side: :short, entry_price: BigDecimal("100"), stop_price: BigDecimal("102"))
      expect(alloc.target_price).to eq(BigDecimal("90"))
      expect(alloc.rr).to be > 0
    end
  end
end
