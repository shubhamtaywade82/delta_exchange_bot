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
        "timeframes" => { "trend" => "1h", "confirm" => "15m", "entry" => "5m" },
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
        { "symbol" => "BTCUSD", "leverage" => 10 }
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
    expect(config.symbols).to eq([{ symbol: "BTCUSD", leverage: 10 }])
  end

  it "memoizes symbols" do
    expect(config.symbols).to be(config.symbols)
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

  it "exposes max_margin_per_position_pct" do
    expect(config.max_margin_per_position_pct).to eq(40.0)
  end

  it "exposes timeframes" do
    expect(config.timeframe_trend).to eq("1h")
    expect(config.timeframe_confirm).to eq("15m")
    expect(config.timeframe_entry).to eq("5m")
  end

  it "exposes leverage for a symbol" do
    expect(config.leverage_for("BTCUSD")).to eq(10)
  end

  # ---------------------------------------------------------------------------
  # mode
  # ---------------------------------------------------------------------------

  context "with invalid mode" do
    it "raises on invalid mode" do
      bad = valid_yaml.merge("mode" => "invalid")
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /mode/)
    end
  end

  context "with missing mode key" do
    it "raises ValidationError (not KeyError)" do
      bad = valid_yaml.reject { |k, _| k == "mode" }
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /mode is required/)
    end
  end

  # ---------------------------------------------------------------------------
  # symbols
  # ---------------------------------------------------------------------------

  context "with empty symbols" do
    it "raises on empty symbols list" do
      bad = valid_yaml.merge("symbols" => [])
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /symbols/)
    end
  end

  context "with a blank symbol name" do
    it "raises" do
      bad = valid_yaml.merge("symbols" => [{ "symbol" => "  ", "leverage" => 10 }])
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /symbol name must not be blank/)
    end
  end

  context "with missing symbols key" do
    it "raises ValidationError (not NoMethodError) when symbols key is absent" do
      bad = valid_yaml.reject { |k, _| k == "symbols" }
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /symbols/)
    end
  end

  # ---------------------------------------------------------------------------
  # risk fields
  # ---------------------------------------------------------------------------

  context "with out-of-range risk_per_trade_pct" do
    it "raises when > 10" do
      bad = valid_yaml.dup
      bad["risk"] = valid_yaml["risk"].merge("risk_per_trade_pct" => 15)
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /risk_per_trade_pct/)
    end
  end

  context "with out-of-range max_margin_per_position_pct" do
    it "raises when < 5.0" do
      bad = valid_yaml.dup
      bad["risk"] = valid_yaml["risk"].merge("max_margin_per_position_pct" => 3)
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /max_margin_per_position_pct/)
    end

    it "raises when > 100.0" do
      bad = valid_yaml.dup
      bad["risk"] = valid_yaml["risk"].merge("max_margin_per_position_pct" => 110)
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /max_margin_per_position_pct/)
    end
  end

  context "with usd_to_inr_rate at zero" do
    it "raises" do
      bad = valid_yaml.dup
      bad["risk"] = valid_yaml["risk"].merge("usd_to_inr_rate" => 0)
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /usd_to_inr_rate/)
    end
  end

  # ---------------------------------------------------------------------------
  # strategy fields
  # ---------------------------------------------------------------------------

  context "with out-of-range trailing_stop_pct" do
    it "raises when > 20" do
      bad = valid_yaml.dup
      bad["strategy"] = valid_yaml["strategy"].merge("trailing_stop_pct" => 25)
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /trailing_stop_pct/)
    end

    it "raises when < 0.1" do
      bad = valid_yaml.dup
      bad["strategy"] = valid_yaml["strategy"].merge("trailing_stop_pct" => 0.0)
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /trailing_stop_pct/)
    end
  end

  context "with out-of-range supertrend_atr_period" do
    it "raises when > 50" do
      bad = valid_yaml.dup
      bad["strategy"] = valid_yaml["strategy"].merge(
        "supertrend" => { "atr_period" => 55, "multiplier" => 3.0 }
      )
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /atr_period/)
    end

    it "raises when missing (nil coercion prevented)" do
      bad = valid_yaml.dup
      bad["strategy"] = valid_yaml["strategy"].merge(
        "supertrend" => { "multiplier" => 3.0 }
      )
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /strategy\.supertrend\.atr_period is required/)
    end
  end

  context "with out-of-range adx_period" do
    it "raises when > 50" do
      bad = valid_yaml.dup
      bad["strategy"] = valid_yaml["strategy"].merge(
        "adx" => { "period" => 60, "threshold" => 25 }
      )
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /adx\.period/)
    end
  end

  context "with min_candles_required > candles_lookback" do
    it "raises" do
      bad = valid_yaml.dup
      bad["strategy"] = valid_yaml["strategy"].merge(
        "min_candles_required" => 150,
        "candles_lookback" => 100
      )
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /min_candles_required must be <= candles_lookback/)
    end
  end

  # ---------------------------------------------------------------------------
  # telegram
  # ---------------------------------------------------------------------------

  context "with telegram enabled but blank token" do
    it "raises" do
      bad = valid_yaml.dup
      bad["notifications"] = valid_yaml["notifications"].merge(
        "telegram" => { "enabled" => true, "bot_token" => "", "chat_id" => "12345" }
      )
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /telegram\.bot_token must not be blank/)
    end
  end

  context "with telegram enabled but blank chat_id" do
    it "raises" do
      bad = valid_yaml.dup
      bad["notifications"] = valid_yaml["notifications"].merge(
        "telegram" => { "enabled" => true, "bot_token" => "tok123", "chat_id" => "" }
      )
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /telegram\.chat_id must not be blank/)
    end
  end

  # ---------------------------------------------------------------------------
  # daily_summary_time
  # ---------------------------------------------------------------------------

  context "with invalid daily_summary_time format" do
    it "raises on non-HH:MM format" do
      bad = valid_yaml.dup
      bad["notifications"] = valid_yaml["notifications"].merge("daily_summary_time" => "6pm")
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /daily_summary_time must be in HH:MM format/)
    end

    it "raises on single-digit hour" do
      bad = valid_yaml.dup
      bad["notifications"] = valid_yaml["notifications"].merge("daily_summary_time" => "8:00")
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /daily_summary_time must be in HH:MM format/)
    end
  end

  context "with invalid daily_summary_time" do
    it "raises on out-of-range time" do
      bad = valid_yaml.dup
      bad["notifications"] = valid_yaml["notifications"].merge("daily_summary_time" => "25:00")
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /daily_summary_time/)
    end
  end

  # ---------------------------------------------------------------------------
  # log_level
  # ---------------------------------------------------------------------------

  context "with invalid log_level" do
    it "raises" do
      bad = valid_yaml.dup
      bad["logging"] = { "level" => "verbose", "file" => "logs/bot.log" }
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /log_level must be one of/)
    end
  end

  # ---------------------------------------------------------------------------
  # leverage_for sad path
  # ---------------------------------------------------------------------------

  context "leverage_for with unknown symbol" do
    it "raises ArgumentError" do
      expect { config.leverage_for("UNKNOWN") }.to raise_error(ArgumentError, /Unknown symbol/)
    end
  end
end
