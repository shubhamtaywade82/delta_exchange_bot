# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::Fees do
  describe ".effective_fee_rate" do
    it "applies default GST multiplier to taker rate" do
      product = build(:paper_product_snapshot, raw_metadata: {})

      effective_rate = described_class.effective_fee_rate(product: product, liquidity: :taker)

      expect(effective_rate).to eq(BigDecimal("0.00059"))
    end

    it "uses maker fee rate when fill liquidity is maker" do
      product = build(:paper_product_snapshot, raw_metadata: { "maker_fee_rate" => "0.0002", "gst_multiplier" => "1.18" })

      effective_rate = described_class.effective_fee_rate(product: product, liquidity: :maker)

      expect(effective_rate).to eq(BigDecimal("0.000236"))
    end
  end
end
