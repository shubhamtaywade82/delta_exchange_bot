# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::DigestBuilder do
  def candle_row(i, close_delta: 1.0)
    base = 100.0 + (i * close_delta)
    t = i * 300
    {
      open: base - 0.5,
      high: base + 1.0,
      low: base - 1.0,
      close: base,
      volume: 10.0,
      timestamp: t
    }
  end

  def candle_set(n)
    (0...n).map { |i| candle_row(i) }
  end

  let(:config) do
    instance_double(
      Bot::Config,
      candles_lookback: 40,
      min_candles_required: 15,
      timeframe_trend: "1h",
      timeframe_confirm: "15m",
      timeframe_entry: "5m",
      adx_period: 14,
      adx_threshold: 20,
      supertrend_indicator_type: nil,
      supertrend_variant: "classic",
      supertrend_atr_period: 10,
      supertrend_multiplier: 3.0,
      ml_adaptive_supertrend_training_period: 100,
      ml_adaptive_supertrend_highvol: 0.75,
      ml_adaptive_supertrend_midvol: 0.5,
      ml_adaptive_supertrend_lowvol: 0.25
    )
  end

  let(:candles) { candle_set(40) }
  let(:market_data) { instance_double("MarketData") }

  before do
    allow(Trading::Analysis::HistoricalCandles).to receive(:fetch).and_return(candles)
    allow(Rails.cache).to receive(:read).with("ltp:BTCUSD").and_return(105.25)
  end

  it "returns structure, smc, and timeframes without error" do
    digest = described_class.call(symbol: "BTCUSD", market_data: market_data, config: config)

    expect(digest[:error]).to be_nil
    expect(digest[:symbol]).to eq("BTCUSD")
    expect(digest[:market_structure]).to include(:bias, :h1, :m15, :m5, :adx)
    expect(digest[:smc]).to include(:bos, :order_blocks)
    expect(digest[:timeframes].keys.map(&:to_s)).to contain_exactly("trend", "confirm", "entry")
  end
end
