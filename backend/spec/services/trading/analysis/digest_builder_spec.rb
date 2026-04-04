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
    allow(Trading::Analysis::AiSmcSynthesizer).to receive(:call).and_return(nil)
  end

  it "forwards ollama_connection_settings into AiSmcSynthesizer" do
    settings = Ai::OllamaClient.read_connection_settings
    allow(Trading::Analysis::AiSmcSynthesizer).to receive(:call).and_return(nil)
    described_class.call(
      symbol: "BTCUSD",
      market_data: market_data,
      config: config,
      ollama_connection_settings: settings
    )
    expect(Trading::Analysis::AiSmcSynthesizer).to have_received(:call).with(
      hash_including(symbol: "BTCUSD", connection_settings: settings)
    )
  end

  it "returns structure, multi-timeframe SMC, trade plan, and timeframes without error" do
    digest = described_class.call(symbol: "BTCUSD", market_data: market_data, config: config)

    expect(digest[:error]).to be_nil
    expect(digest[:symbol]).to eq("BTCUSD")
    expect(digest[:market_structure]).to include(:bias, :h1, :m15, :m5, :adx)
    expect(digest[:smc]).to include(:bos, :order_blocks)
    expect(digest[:smc_by_timeframe].keys.map(&:to_s)).to contain_exactly("5m", "15m", "1h")
    expect(digest[:smc_by_timeframe]["5m"]).to include("structure_sequence", "premium_discount", "entry_model_flags")
    expect(digest[:smc_confluence_mtf]).to be_a(Hash)
    expect(digest[:smc_confluence_mtf]["kind"]).to eq("smc_confluence_mtf")
    expect(digest[:smc_confluence_mtf]["timeframes"].keys.map(&:to_s)).to contain_exactly("5m", "15m", "1h")
    expect(digest[:smc_model_version]).to eq("2")
    expect(digest[:mtf_alignment]).to include(:htf_1h_trend_type)
    expect(digest[:trade_plan]).to include("direction")
    expect(digest[:timeframes].keys.map(&:to_s)).to contain_exactly("trend", "confirm", "entry")
  end
end
