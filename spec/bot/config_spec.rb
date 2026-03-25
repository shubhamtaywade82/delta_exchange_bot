# frozen_string_literal: true

require "spec_helper"
require "bot/config"

RSpec.describe Bot::Config do
  let(:valid_yaml) do
    {
      "mode" => "testnet",
      "strategy" => {
        "supertrend" => { "atr_period" => 10, "multiplier" => 3.0 },
        "adx" => { "period" => 14, "threshold" => 25 },
        "trailing_stop_pct" => 1.5,
        "timeframes" => { "trend" => "60", "confirm" => "15", "entry" => "5" },
        "candles_lookback" => 100,
        "min_candles_required" => 30
      },
      "risk" => {
        "risk_per_trade_pct" => 1.5,
        "max_concurrent_positions" => 5,
        "max_margin_per_position_pct" => 40,
        "usd_to_inr_rate" => 85.0
      },
      "symbols" => [
        { "symbol" => "BTCUSDT", "leverage" => 10 }
      ],
      "notifications" => {
        "telegram" => { "enabled" => false, "bot_token" => "", "chat_id" => "" },
        "daily_summary_time" => "18:00"
      },
      "logging" => { "level" => "info", "file" => "logs/bot.log" }
    }
  end

  subject(:config) { described_class.new(valid_yaml) }

  it "exposes mode" do
    expect(config.mode).to eq("testnet")
  end

  it "exposes symbols with leverage" do
    expect(config.symbols).to eq([{ symbol: "BTCUSDT", leverage: 10 }])
  end

  it "exposes supertrend config" do
    expect(config.supertrend_atr_period).to eq(10)
    expect(config.supertrend_multiplier).to eq(3.0)
  end

  it "exposes adx config" do
    expect(config.adx_period).to eq(14)
    expect(config.adx_threshold).to eq(25)
  end

  it "exposes risk config" do
    expect(config.risk_per_trade_pct).to eq(1.5)
    expect(config.max_concurrent_positions).to eq(5)
    expect(config.usd_to_inr_rate).to eq(85.0)
  end

  it "exposes timeframes" do
    expect(config.timeframe_trend).to eq("60")
    expect(config.timeframe_confirm).to eq("15")
    expect(config.timeframe_entry).to eq("5")
  end

  it "exposes leverage for a symbol" do
    expect(config.leverage_for("BTCUSDT")).to eq(10)
  end

  context "with invalid mode" do
    it "raises on invalid mode" do
      bad = valid_yaml.merge("mode" => "invalid")
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /mode/)
    end
  end

  context "with out-of-range risk_per_trade_pct" do
    it "raises when > 10" do
      bad = valid_yaml.dup
      bad["risk"] = valid_yaml["risk"].merge("risk_per_trade_pct" => 15)
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /risk_per_trade_pct/)
    end
  end

  context "with empty symbols" do
    it "raises on empty symbols list" do
      bad = valid_yaml.merge("symbols" => [])
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /symbols/)
    end
  end
end
