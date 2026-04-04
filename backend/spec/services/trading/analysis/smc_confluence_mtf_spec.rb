# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::SmcConfluenceMtf do
  def candle(i, close: 100.0 + i)
    {
      timestamp: i * 300,
      open: close - 0.5,
      high: close + 1.0,
      low: close - 1.0,
      close: close,
      volume: 10.0
    }
  end

  describe ".from_timeframe_candles" do
    it "returns schema, per-timeframe confluence, and alignment maps" do
      rows = (0...50).map { |i| candle(i) }
      payload = described_class.from_timeframe_candles(
        symbol: "BTCUSD",
        timeframe_candles: { "5m" => rows, "15m" => rows, "1h" => rows }
      )

      expect(payload["kind"]).to eq("smc_confluence_mtf")
      expect(payload["symbol"]).to eq("BTCUSD")
      expect(payload["timeframes"].keys.map(&:to_s)).to contain_exactly("5m", "15m", "1h")

      %w[5m 15m 1h].each do |tf|
        block = payload["timeframes"][tf]
        expect(block["candle_count"]).to eq(50)
        expect(block["confluence"]).to be_a(Hash)
        expect(block["confluence"]).to include("long_score", "short_score", "choch_bull", "structure_bias")
        expect(block["last_close"]).to be_a(Float)
      end

      align = payload["alignment"]
      expect(align["long_signal"].keys.map(&:to_s)).to include("5m", "15m", "1h")
      expect(align["structure_bias"]).to be_a(Hash)
    end

    it "coerces trendline break flags to booleans inside confluence" do
      rows = (0...30).map { |i| candle(i) }
      payload = described_class.from_timeframe_candles(
        symbol: "ETHUSD",
        timeframe_candles: { "5m" => rows }
      )
      br = payload["timeframes"]["5m"]["confluence"]
      expect(br["tl_bear_break"]).to be_in([ true, false ])
      expect(br["tl_bull_break"]).to be_in([ true, false ])
    end
  end
end
