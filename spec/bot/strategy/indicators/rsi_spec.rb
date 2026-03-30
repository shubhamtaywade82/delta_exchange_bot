# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/indicators/rsi"

RSpec.describe Bot::Strategy::Indicators::RSI do
  let(:candles) do
    prices = [100, 102, 104, 106, 108, 110, 112, 114, 116, 118,
              116, 114, 112, 110, 108, 106, 104, 102, 100, 98]
    prices.map { |c| { close: c.to_f } }
  end

  describe ".compute" do
    subject(:result) { described_class.compute(candles, period: 5) }

    it "returns one result per candle" do
      expect(result.size).to eq(candles.size)
    end

    it "returns nil value for bars before enough data" do
      expect(result.first[:value]).to be_nil
    end

    it "returns a Float value after enough bars" do
      expect(result.last[:value]).to be_a(Float)
    end

    it "RSI is between 0 and 100" do
      non_nil = result.reject { |r| r[:value].nil? }
      non_nil.each { |r| expect(r[:value]).to be_between(0.0, 100.0) }
    end

    it "marks overbought when RSI above 70" do
      up_candles = (1..20).map { |i| { close: (100 + i).to_f } }
      r = described_class.compute(up_candles, period: 5)
      last_rsi = r.last
      expect(last_rsi[:overbought]).to eq(last_rsi[:value] > 70)
    end

    it "marks oversold when RSI below 30" do
      down_candles = (0..19).map { |i| { close: (100 - i).to_f } }
      r = described_class.compute(down_candles, period: 5)
      last_rsi = r.last
      expect(last_rsi[:oversold]).to eq(last_rsi[:value] < 30)
    end

    it "returns all nil results when candle count <= period" do
      short = candles.first(5)
      r = described_class.compute(short, period: 5)
      expect(r.all? { |x| x[:value].nil? }).to be true
    end
  end
end
