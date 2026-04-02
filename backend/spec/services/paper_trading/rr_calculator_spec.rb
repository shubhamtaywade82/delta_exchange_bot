# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::RrCalculator do
  it "computes 5:1 RR for long with 10% target and 2% stop" do
    result = described_class.call(
      side: :buy,
      entry_price: "1000",
      stop_price: "980",
      target_profit_pct: BigDecimal("0.10")
    )
    expect(result[:target_price]).to eq(BigDecimal("1100"))
    expect(result[:reward]).to eq(BigDecimal("100"))
    expect(result[:risk]).to eq(BigDecimal("20"))
    expect(result[:rr]).to eq(BigDecimal("5"))
  end

  it "raises when risk is zero" do
    expect do
      described_class.call(side: :buy, entry_price: "100", stop_price: "100")
    end.to raise_error(ArgumentError, /risk must be > 0/)
  end
end
