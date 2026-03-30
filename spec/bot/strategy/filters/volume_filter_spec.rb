# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/filters/volume_filter"

RSpec.describe Bot::Strategy::Filters::VolumeFilter do
  def cvd(trend)    = { delta_trend: trend, cumulative_delta: 1000.0 }
  def vwap(above)   = { vwap: 100.0, deviation_pct: 0.5, price_above: above }

  describe ".check" do
    context "long signal" do
      it "passes when CVD is bullish and price is above VWAP" do
        result = described_class.check(:long, cvd(:bullish), 101.0, vwap(true))
        expect(result[:passed]).to eq(true)
      end

      it "blocks when CVD is bearish" do
        result = described_class.check(:long, cvd(:bearish), 101.0, vwap(true))
        expect(result[:passed]).to eq(false)
        expect(result[:reason]).to include("CVD")
      end

      it "blocks when price is below VWAP" do
        result = described_class.check(:long, cvd(:bullish), 99.0, vwap(false))
        expect(result[:passed]).to eq(false)
        expect(result[:reason]).to include("VWAP")
      end
    end

    context "short signal" do
      it "passes when CVD is bearish and price is below VWAP" do
        result = described_class.check(:short, cvd(:bearish), 99.0, vwap(false))
        expect(result[:passed]).to eq(true)
      end

      it "blocks when CVD is bullish" do
        result = described_class.check(:short, cvd(:bullish), 99.0, vwap(false))
        expect(result[:passed]).to eq(false)
      end

      it "blocks when price is above VWAP" do
        result = described_class.check(:short, cvd(:bearish), 101.0, vwap(true))
        expect(result[:passed]).to eq(false)
      end
    end

    it "passes when cvd_data is nil (store not yet populated)" do
      result = described_class.check(:long, nil, 101.0, vwap(true))
      expect(result[:passed]).to eq(true)
      expect(result[:reason]).to include("unavailable")
    end

    it "passes when vwap_result is nil" do
      result = described_class.check(:long, cvd(:bullish), 101.0, nil)
      expect(result[:passed]).to eq(true)
      expect(result[:reason]).to include("unavailable")
    end
  end
end
