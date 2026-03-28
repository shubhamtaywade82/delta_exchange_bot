# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/filters/momentum_filter"

RSpec.describe Bot::Strategy::Filters::MomentumFilter do
  def rsi(value)
    { value: value, overbought: value > 70, oversold: value < 30 }
  end

  describe ".check" do
    it "passes for long when RSI is neutral (between 30-70)" do
      result = described_class.check(:long, rsi(55.0))
      expect(result[:passed]).to eq(true)
    end

    it "blocks long when RSI is overbought (> 70)" do
      result = described_class.check(:long, rsi(75.0))
      expect(result[:passed]).to eq(false)
      expect(result[:reason]).to include("RSI")
    end

    it "passes for short when RSI is neutral" do
      result = described_class.check(:short, rsi(45.0))
      expect(result[:passed]).to eq(true)
    end

    it "blocks short when RSI is oversold (< 30)" do
      result = described_class.check(:short, rsi(25.0))
      expect(result[:passed]).to eq(false)
      expect(result[:reason]).to include("RSI")
    end

    it "passes for short when RSI is overbought" do
      result = described_class.check(:short, rsi(80.0))
      expect(result[:passed]).to eq(true)
    end

    it "passes for long when RSI is oversold" do
      result = described_class.check(:long, rsi(20.0))
      expect(result[:passed]).to eq(true)
    end

    it "passes when rsi_result is nil (store not yet populated)" do
      result = described_class.check(:long, nil)
      expect(result[:passed]).to eq(true)
      expect(result[:reason]).to include("unavailable")
    end
  end
end
