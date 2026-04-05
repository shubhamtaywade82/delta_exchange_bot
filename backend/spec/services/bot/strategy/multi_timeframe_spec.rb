# frozen_string_literal: true

require "benchmark"
require "rails_helper"

RSpec.describe Bot::Strategy::MultiTimeframe do
  let(:config) do
    double(
      timeframe_trend: "4h", timeframe_confirm: "1h", timeframe_entry: "5m",
      supertrend_atr_period: 3, supertrend_multiplier: 1.5,
      supertrend_variant: "classic", supertrend_indicator_type: "supertrend",
      effective_min_candles_for_supertrend: 10,
      adx_period: 5, adx_threshold: 20,
      candles_lookback: 20, min_candles_required: 10,
      dry_run?: true
    )
  end

  let(:market_data) { double("MarketData") }
  let(:logger) { double("Logger", debug: nil, warn: nil, info: nil, error: nil) }

  subject(:mtf) { described_class.new(config: config, market_data: market_data, logger: logger) }

  let(:heavy_buy_trades) { Array.new(30) { { "side" => "buy", "size" => "1.0" } } }

  # Build 19 bearish candles followed by 1 strongly bullish candle (flip to :bullish on last bar)
  def build_flip_up_candles(n = 20)
    base_time = Time.now.to_i - n * 300
    (0...n).map do |i|
      ts = base_time + i * 300
      if i < n - 1
        base = 200.0 - i * 2
        { open: base - 0.5, high: base + 2.0, low: base - 2.0, close: base, timestamp: ts, volume: 1000.0 }
      else
        # Last bar: massive bullish candle that closes above the upper Supertrend band
        { open: 162.0, high: 210.0, low: 160.0, close: 208.0, timestamp: ts, volume: 1000.0 }
      end
    end
  end

  # Build steadily falling candles (stays bearish throughout)
  def build_candles_down(n = 20)
    base_time = Time.now.to_i - n * 300
    (0...n).map do |i|
      base = 200.0 - i * 2
      { open: base - 0.5, high: base + 2.0, low: base - 2.0, close: base,
        timestamp: base_time + i * 300, volume: 1000.0 }
    end
  end

  context "when all three timeframes flip bullish on the last bar" do
    before do
      allow(market_data).to receive(:candles).and_return(build_flip_up_candles)
      allow(market_data).to receive(:trades).and_return(heavy_buy_trades)
    end

    it "emits a LONG signal" do
      signal = mtf.evaluate("BTCUSD", current_price: 208.0)
      expect(signal&.side).to eq(:long)
      expect(signal&.symbol).to eq("BTCUSD")
    end
  end

  context "when trend timeframe is bearish but confirm and entry flip bullish" do
    before do
      call_count = 0
      allow(market_data).to receive(:candles) do |_params|
        call_count += 1
        call_count == 1 ? build_candles_down : build_flip_up_candles
      end
      allow(market_data).to receive(:trades).and_return(nil)
    end

    it "returns nil (no confluent signal)" do
      expect(mtf.evaluate("BTCUSD", current_price: 208.0)).to be_nil
    end
  end

  context "when candles are insufficient" do
    let(:redis_mock) { instance_double(Redis) }

    before do
      allow(redis_mock).to receive(:hset)
      allow(Redis).to receive(:new).and_return(redis_mock)
      stub_const("#{described_class}::CANDLE_FETCH_MAX_ATTEMPTS", 1)
      stub_const("#{described_class}::CANDLE_RESOLUTION_STAGGER_S", 0.0)
      allow(market_data).to receive(:trades).and_return(nil)
      n = 5
      base_time = Time.now.to_i - n * 300
      short_candles = (0...n).map do |i|
        base = 100.0 + i * 2
        { open: base - 0.5, high: base + 2.0, low: base - 2.0, close: base,
          timestamp: base_time + i * 300, volume: 1000.0 }
      end
      allow(market_data).to receive(:candles).and_return(short_candles)
    end

    it "returns nil, logs a warning, and persists blocked evaluation state with a fresh updated_at" do
      allow(logger).to receive(:warn)
      expect(mtf.evaluate("BTCUSD", current_price: 100.0)).to be_nil
      expect(logger).to have_received(:warn).with(a_string_including("insufficient_candles")).at_least(:once)

      expect(redis_mock).to have_received(:hset).with(
        "delta:strategy:state",
        "BTCUSD",
        satisfy { |json|
          payload = JSON.parse(json, symbolize_names: true)
          payload[:evaluation_blocked] == true &&
            payload[:evaluation_block_reason] == "insufficient_candles" &&
            payload[:updated_at].present?
        }
      )
    end
  end

  context "stale signal prevention" do
    before do
      allow(market_data).to receive(:candles).and_return(build_flip_up_candles)
      allow(market_data).to receive(:trades).and_return(heavy_buy_trades)
    end

    it "does not re-emit a signal for the same candle timestamp" do
      first  = mtf.evaluate("BTCUSD", current_price: 208.0)
      second = mtf.evaluate("BTCUSD", current_price: 208.0)
      expect(first&.side).to eq(:long)
      expect(second).to be_nil
    end
  end

  context "when REST trades stall (no read timeout upstream)" do
    before do
      stub_const("#{described_class}::REST_FETCH_TIMEOUT_S", 1)
      allow(market_data).to receive(:candles).and_return(build_flip_up_candles)
      allow(market_data).to receive(:trades) { sleep 3; { "result" => [] } }
      allow(DeltaExchange::Models::Ticker).to receive(:find).and_return(nil)
    end

    it "times out, warns, and returns without hanging the caller" do
      expect(logger).to receive(:warn).with(a_string_including("trades_fetch_timeout", "BTCUSD"))
      elapsed = Benchmark.realtime { mtf.evaluate("BTCUSD", current_price: 208.0) }
      expect(elapsed).to be < 3.0
    end
  end
end
