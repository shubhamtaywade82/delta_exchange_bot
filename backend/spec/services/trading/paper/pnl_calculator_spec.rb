# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Paper::PnlCalculator do
  describe ".call" do
    it "computes long gross and net after fees" do
      r = described_class.call(
        side: :long,
        entry_price: BigDecimal("100"),
        exit_price: BigDecimal("110"),
        quantity: BigDecimal("2"),
        risk_unit_value: BigDecimal("1"),
        fees: BigDecimal("1")
      )
      expect(r.gross_pnl).to eq(BigDecimal("20"))
      expect(r.net_pnl).to eq(BigDecimal("19"))
    end

    it "computes short pnl" do
      r = described_class.call(
        side: :short,
        entry_price: BigDecimal("100"),
        exit_price: BigDecimal("90"),
        quantity: BigDecimal("3"),
        risk_unit_value: BigDecimal("1")
      )
      expect(r.gross_pnl).to eq(BigDecimal("30"))
    end
  end

  describe ".realized_for_partial_fills" do
    it "uses weighted average exit from fills" do
      fills = [
        { price: BigDecimal("100"), size: BigDecimal("1") },
        { price: BigDecimal("110"), size: BigDecimal("1") }
      ]
      r = described_class.realized_for_partial_fills(
        side: :long,
        fills: fills,
        entry_avg: BigDecimal("90"),
        risk_unit_value: BigDecimal("1")
      )
      expect(r.gross_pnl).to eq((BigDecimal("105") - BigDecimal("90")) * BigDecimal("2"))
    end
  end
end
