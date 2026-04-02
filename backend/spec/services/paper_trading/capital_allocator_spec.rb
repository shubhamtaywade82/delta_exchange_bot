# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::CapitalAllocator do
  subject(:allocator) do
    described_class.new(
      equity: BigDecimal("100_000"),
      risk_pct: BigDecimal("0.01"),
      target_profit_pct: BigDecimal("0.10"),
      risk_unit_value: BigDecimal("0.001")
    )
  end

  describe "#call (long)" do
    let(:allocation) { allocator.call(side: :buy, entry_price: "50000", stop_price: "49000") }

    it "computes risk_budget as 1% of equity" do
      expect(allocation.risk_budget).to eq(BigDecimal("1000"))
    end

    it "computes per_unit_risk using risk_unit_value" do
      expect(allocation.per_unit_risk).to eq(BigDecimal("1"))
    end

    it "allocates quantity = floor(risk_budget / per_unit_risk)" do
      expect(allocation.quantity).to eq(1000)
    end

    it "sets 10% target price above entry for long" do
      expect(allocation.target_price).to eq(BigDecimal("55000"))
    end

    it "computes RR = 5:1" do
      expect(allocation.rr).to eq(BigDecimal("5"))
    end

    it "is valid" do
      expect(allocation.valid?).to be true
    end
  end

  describe "#call (short)" do
    let(:allocation) { allocator.call(side: :sell, entry_price: "50000", stop_price: "51000") }

    it "sets target below entry for short" do
      expect(allocation.target_price).to eq(BigDecimal("45000"))
    end

    it "is valid" do
      expect(allocation.valid?).to be true
    end
  end

  describe "quantity below 1" do
    it "returns invalid allocation" do
      tiny = described_class.new(
        equity: BigDecimal("10"),
        risk_pct: BigDecimal("0.01"),
        risk_unit_value: BigDecimal("1")
      )
      allocation = tiny.call(side: :buy, entry_price: "50000", stop_price: "49000")
      expect(allocation.valid?).to be false
      expect(allocation.quantity).to eq(0)
    end
  end

  it "raises on invalid side" do
    expect { allocator.call(side: :flat, entry_price: "100", stop_price: "90") }
      .to raise_error(ArgumentError, /invalid side/)
  end
end
