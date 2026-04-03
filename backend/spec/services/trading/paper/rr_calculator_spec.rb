# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Paper::RrCalculator do
  describe ".call" do
    it "returns RR for long with 10% target" do
      r = described_class.call(
        side: :long,
        entry_price: BigDecimal("100"),
        stop_price: BigDecimal("98"),
        target_profit_pct: BigDecimal("0.10")
      )
      expect(r.target_price).to eq(BigDecimal("110"))
      expect(r.risk).to eq(BigDecimal("2"))
      expect(r.reward).to eq(BigDecimal("10"))
      expect(r.rr).to eq(BigDecimal("5"))
    end

    it "returns RR for short" do
      r = described_class.call(
        side: :short,
        entry_price: BigDecimal("100"),
        stop_price: BigDecimal("102")
      )
      expect(r.target_price).to eq(BigDecimal("90"))
      expect(r.risk).to eq(BigDecimal("2"))
      expect(r.reward).to eq(BigDecimal("10"))
      expect(r.rr).to eq(BigDecimal("5"))
    end

    it "raises when risk is zero" do
      expect do
        described_class.call(side: :long, entry_price: "100", stop_price: "100")
      end.to raise_error(ArgumentError, /risk must be > 0/)
    end
  end
end
