# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Strategy::IndicatorFactory do
  def candle(ts, o, h, l, c)
    { open: o, high: h, low: l, close: c, timestamp: ts }
  end

  let(:candles) { 25.times.map { |i| candle(i, 100, 101, 99, 100.5) } }

  let(:classic_config) do
    instance_double(
      Bot::Config,
      supertrend_variant: "classic",
      supertrend_indicator_type: "supertrend",
      supertrend_atr_period: 10,
      supertrend_multiplier: 2.0,
      ml_adaptive_supertrend_training_period: 100,
      ml_adaptive_supertrend_highvol: 0.75,
      ml_adaptive_supertrend_midvol: 0.5,
      ml_adaptive_supertrend_lowvol: 0.25
    )
  end

  let(:ml_config) do
    instance_double(
      Bot::Config,
      supertrend_variant: "ml_adaptive",
      supertrend_indicator_type: "supertrend",
      supertrend_atr_period: 10,
      supertrend_multiplier: 1.0,
      ml_adaptive_supertrend_training_period: 20,
      ml_adaptive_supertrend_highvol: 0.75,
      ml_adaptive_supertrend_midvol: 0.5,
      ml_adaptive_supertrend_lowvol: 0.25
    )
  end

  it "uses classic Supertrend by default" do
    out = described_class.compute_supertrend(candles, config: classic_config)
    expect(out.size).to eq(candles.size)
    expect(out.last[:direction]).to be_in(%i[bullish bearish nil])
  end

  it "uses ML Adaptive Supertrend when variant is ml_adaptive" do
    out = described_class.compute_supertrend(candles, config: ml_config)
    expect(out.size).to eq(candles.size)
  end

  it "maps mast alias to ml adaptive" do
    mast_config = instance_double(
      Bot::Config,
      supertrend_variant: "classic",
      supertrend_indicator_type: "mast",
      supertrend_atr_period: 10,
      supertrend_multiplier: 1.0,
      ml_adaptive_supertrend_training_period: 20,
      ml_adaptive_supertrend_highvol: 0.75,
      ml_adaptive_supertrend_midvol: 0.5,
      ml_adaptive_supertrend_lowvol: 0.25
    )
    expect(described_class.supertrend_kind(mast_config)).to eq(:ml_adaptive)
  end
end
