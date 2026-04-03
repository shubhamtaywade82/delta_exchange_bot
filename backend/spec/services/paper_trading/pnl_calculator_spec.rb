# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::PnlCalculator do
  describe ".call" do
    it "computes long gross and net after fees" do
      result = described_class.call(
        side: :buy,
        entry_price: "100",
        exit_price: "110",
        quantity: 10,
        risk_unit_value: "0.001",
        fees: "0.5"
      )
      expect(result[:gross_pnl]).to eq(BigDecimal("0.1"))
      expect(result[:net_pnl]).to eq(BigDecimal("-0.4"))
    end

    it "computes short profit when price drops" do
      result = described_class.call(
        side: :sell,
        entry_price: "100",
        exit_price: "90",
        quantity: 5,
        risk_unit_value: "1"
      )
      expect(result[:gross_pnl]).to eq(BigDecimal("50"))
    end
  end

  describe ".realized_for_partial_fills" do
    it "uses weighted average exit" do
      fills = [
        { price: "105", size: 3 },
        { price: "110", size: 7 }
      ]
      result = described_class.realized_for_partial_fills(
        side: :buy,
        fills: fills,
        entry_avg: "100",
        risk_unit_value: "1"
      )
      expect(result[:gross_pnl]).to eq(BigDecimal("85"))
    end
  end
end
