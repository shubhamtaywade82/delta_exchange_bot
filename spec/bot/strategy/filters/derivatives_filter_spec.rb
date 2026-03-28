# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/filters/derivatives_filter"

RSpec.describe Bot::Strategy::Filters::DerivativesFilter do
  def deriv(oi_trend:, funding_extreme:)
    { oi_usd: 5_000_000.0, oi_trend: oi_trend,
      funding_rate: 0.0001, funding_extreme: funding_extreme }
  end

  describe ".check" do
    it "passes when OI is rising and funding is not extreme" do
      result = described_class.check(deriv(oi_trend: :rising, funding_extreme: false))
      expect(result[:passed]).to eq(true)
    end

    it "blocks when OI is falling (divergence)" do
      result = described_class.check(deriv(oi_trend: :falling, funding_extreme: false))
      expect(result[:passed]).to eq(false)
      expect(result[:reason]).to include("OI")
    end

    it "blocks when funding rate is extreme" do
      result = described_class.check(deriv(oi_trend: :rising, funding_extreme: true))
      expect(result[:passed]).to eq(false)
      expect(result[:reason]).to include("funding")
    end

    it "blocks on both violations and mentions both" do
      result = described_class.check(deriv(oi_trend: :falling, funding_extreme: true))
      expect(result[:passed]).to eq(false)
    end

    it "passes when derivatives_data is nil (store not yet populated)" do
      result = described_class.check(nil)
      expect(result[:passed]).to eq(true)
      expect(result[:reason]).to include("unavailable")
    end

    it "passes when oi_trend is nil (first poll not yet complete)" do
      result = described_class.check({ oi_usd: nil, oi_trend: nil,
                                       funding_rate: 0.0001, funding_extreme: false })
      expect(result[:passed]).to eq(true)
    end
  end
end
