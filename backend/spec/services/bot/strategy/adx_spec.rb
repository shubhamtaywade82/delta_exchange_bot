# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Strategy::ADX do
  # 40 candles: strong uptrend for first 20, then ranging
  let(:trending_candles) do
    (0...40).map do |i|
      base = 100.0 + (i < 20 ? i * 2 : 40.0)
      { high: base + 2.0, low: base - 2.0, close: base + 0.5 }
    end
  end

  subject(:result) { described_class.compute(trending_candles, period: 14) }

  it "returns one result per candle" do
    expect(result.size).to eq(trending_candles.size)
  end

  it "returns hash with :adx, :plus_di, :minus_di" do
    expect(result.last).to include(:adx, :plus_di, :minus_di)
  end

  it "returns nil adx for bars before enough data" do
    expect(result[0][:adx]).to be_nil
  end

  it "returns high ADX during strong trend" do
    adx_values = result[28..].map { |r| r[:adx] }.compact
    expect(adx_values.any? { |v| v > 20 }).to be(true)
  end

  it "returns plus_di > minus_di during uptrend" do
    valid = result.select { |r| r[:adx] }
    uptrend_bars = valid.first(10)
    expect(uptrend_bars.all? { |r| r[:plus_di] > r[:minus_di] }).to be(true)
  end
end
