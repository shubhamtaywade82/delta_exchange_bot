# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/multi_timeframe"
require "bot/strategy/supertrend"
require "bot/strategy/adx"

RSpec.describe Bot::Strategy::MultiTimeframe do
  let(:config) do
    double(
      timeframe_trend: "60", timeframe_confirm: "15", timeframe_entry: "5",
      supertrend_atr_period: 3, supertrend_multiplier: 1.5,
      adx_period: 5, adx_threshold: 20,
      candles_lookback: 20, min_candles_required: 10
    )
  end

  let(:market_data) { double("MarketData") }
  let(:logger) { double("Logger", debug: nil, warn: nil, info: nil, error: nil) }

  subject(:mtf) { described_class.new(config: config, market_data: market_data, logger: logger) }

  # Build 19 bearish candles followed by 1 strongly bullish candle (flip to :bullish on last bar)
  def build_flip_up_candles(n = 20)
    base_time = Time.now.to_i - n * 300
    (0...n).map do |i|
      ts = base_time + i * 300
      if i < n - 1
        base = 200.0 - i * 2
        { open: base - 0.5, high: base + 2.0, low: base - 2.0, close: base, timestamp: ts }
      else
        # Last bar: massive bullish candle that closes above the upper Supertrend band
        { open: 162.0, high: 210.0, low: 160.0, close: 208.0, timestamp: ts }
      end
    end
  end

  # Build steadily falling candles (stays bearish throughout)
  def build_candles_down(n = 20)
    base_time = Time.now.to_i - n * 300
    (0...n).map do |i|
      base = 200.0 - i * 2
      { open: base - 0.5, high: base + 2.0, low: base - 2.0, close: base,
        timestamp: base_time + i * 300 }
    end
  end

  context "when all three timeframes flip bullish on the last bar" do
    before do
      allow(market_data).to receive(:candles).and_return(build_flip_up_candles)
    end

    it "emits a LONG signal" do
      signal = mtf.evaluate("BTCUSDT", current_price: 208.0)
      expect(signal&.side).to eq(:long)
      expect(signal&.symbol).to eq("BTCUSDT")
    end
  end

  context "when 1H is bearish but 15M and 5M flip bullish" do
    before do
      call_count = 0
      allow(market_data).to receive(:candles) do |_params|
        call_count += 1
        call_count == 1 ? build_candles_down : build_flip_up_candles
      end
    end

    it "returns nil (no confluent signal)" do
      expect(mtf.evaluate("BTCUSDT", current_price: 208.0)).to be_nil
    end
  end

  context "when candles are insufficient" do
    before do
      n = 5
      base_time = Time.now.to_i - n * 300
      short_candles = (0...n).map do |i|
        base = 100.0 + i * 2
        { open: base - 0.5, high: base + 2.0, low: base - 2.0, close: base,
          timestamp: base_time + i * 300 }
      end
      allow(market_data).to receive(:candles).and_return(short_candles)
    end

    it "returns nil and logs a warning" do
      expect(logger).to receive(:warn).with("insufficient_candles", anything)
      expect(mtf.evaluate("BTCUSDT", current_price: 100.0)).to be_nil
    end
  end

  context "stale signal prevention" do
    before do
      allow(market_data).to receive(:candles).and_return(build_flip_up_candles)
    end

    it "does not re-emit a signal for the same candle timestamp" do
      first  = mtf.evaluate("BTCUSDT", current_price: 208.0)
      second = mtf.evaluate("BTCUSDT", current_price: 208.0)
      expect(first&.side).to eq(:long)
      expect(second).to be_nil
    end
  end
end
