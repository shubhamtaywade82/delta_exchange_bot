# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::RrPositionSizer do
  it "sizes from max loss INR and caps by margin" do
    result = described_class.compute!(
      max_loss_inr: BigDecimal("85"),
      available_margin_inr: BigDecimal("8500"),
      usd_inr_rate: BigDecimal("85"),
      entry_price: BigDecimal("50_000"),
      stop_price: BigDecimal("49_000"),
      contract_value: BigDecimal("0.001"),
      leverage: 10,
      position_size_limit: nil
    )
    expect(result.final_contracts).to eq(1)
  end

  it "returns zero when stop distance is zero" do
    expect do
      described_class.compute!(
        max_loss_inr: BigDecimal("1000"),
        available_margin_inr: BigDecimal("1_000_000"),
        usd_inr_rate: BigDecimal("85"),
        entry_price: BigDecimal("100"),
        stop_price: BigDecimal("100"),
        contract_value: BigDecimal("1"),
        leverage: 10
      )
    end.to raise_error(ArgumentError, /stop distance/)
  end
end
