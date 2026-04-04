# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Config do
  describe ".load" do
    before { allow(described_class).to receive(:bot_yml_hash).and_return(nil) }

    it "builds runtime config from DB settings and symbol configs" do
      SymbolConfig.create!(symbol: "BTCUSD", leverage: 12, enabled: true)
      Setting.create!(key: "bot.mode", value: "testnet", value_type: "string")
      Setting.create!(key: "strategy.supertrend.atr_period", value: "11", value_type: "integer")
      Setting.create!(key: "strategy.adx.threshold", value: "23", value_type: "float")

      config = described_class.load

      expect(config.mode).to eq("testnet")
      expect(config.symbol_names).to eq(["BTCUSD"])
      expect(config.supertrend_atr_period).to eq(11)
      expect(config.adx_threshold).to eq(23.0)
    end

    it "batch-loads settings in one query instead of per-key find_by" do
      SymbolConfig.create!(symbol: "BTCUSD", leverage: 12, enabled: true)
      Setting.create!(key: "bot.mode", value: "dry_run", value_type: "string")

      expect(Setting).to receive(:where).with(key: described_class::RUNTIME_SETTING_KEYS).once.and_call_original
      expect(Setting).not_to receive(:find_by)

      described_class.load
    end
  end

  describe ".runtime_raw" do
    before do
      SymbolConfig.create!(symbol: "BTCUSD", leverage: 10, enabled: true)
    end

    it "merges notifications.telegram from bot.yml when no DB row overrides" do
      allow(described_class).to receive(:bot_yml_hash).and_return(
        "notifications" => {
          "telegram" => {
            "enabled" => true,
            "bot_token" => "yaml-token",
            "chat_id" => "yaml-chat"
          }
        }
      )

      raw = described_class.runtime_raw
      tg = raw["notifications"]["telegram"]
      expect(tg["enabled"]).to eq(true)
      expect(tg["bot_token"]).to eq("yaml-token")
      expect(tg["chat_id"]).to eq("yaml-chat")
    end

    it "lets DB settings override bot.yml for telegram" do
      allow(described_class).to receive(:bot_yml_hash).and_return(
        "notifications" => {
          "telegram" => {
            "enabled" => true,
            "bot_token" => "yaml-token",
            "chat_id" => "yaml-chat"
          }
        }
      )

      Setting.create!(key: "notifications.telegram.bot_token", value: "db-token", value_type: "string")

      raw = described_class.runtime_raw
      expect(raw.dig("notifications", "telegram", "bot_token")).to eq("db-token")
      expect(raw.dig("notifications", "telegram", "chat_id")).to eq("yaml-chat")
    end

    it "fills blank telegram bot_token from TELEGRAM_BOT_TOKEN after DB merge" do
      allow(described_class).to receive(:bot_yml_hash).and_return(nil)
      Setting.create!(key: "notifications.telegram.enabled", value: "true", value_type: "boolean")
      Setting.create!(key: "notifications.telegram.chat_id", value: "1", value_type: "string")

      old = ENV["TELEGRAM_BOT_TOKEN"]
      begin
        ENV["TELEGRAM_BOT_TOKEN"] = "from-env"
        raw = described_class.runtime_raw
        expect(raw.dig("notifications", "telegram", "bot_token")).to eq("from-env")
      ensure
        if old
          ENV["TELEGRAM_BOT_TOKEN"] = old
        else
          ENV.delete("TELEGRAM_BOT_TOKEN")
        end
      end
    end

    it "sets telegram enabled from TELEGRAM_ENABLED when the variable is present" do
      allow(described_class).to receive(:bot_yml_hash).and_return(
        "notifications" => {
          "telegram" => {
            "enabled" => false,
            "bot_token" => "t",
            "chat_id" => "1"
          }
        }
      )

      old = ENV["TELEGRAM_ENABLED"]
      begin
        ENV["TELEGRAM_ENABLED"] = "1"
        raw = described_class.runtime_raw
        expect(raw.dig("notifications", "telegram", "enabled")).to eq(true)
      ensure
        if old
          ENV["TELEGRAM_ENABLED"] = old
        else
          ENV.delete("TELEGRAM_ENABLED")
        end
      end
    end

    it "includes telegram notification keys in RUNTIME_SETTING_KEYS" do
      keys = described_class::RUNTIME_SETTING_KEYS
      expect(keys).to include(
        "notifications.telegram.enabled",
        "notifications.telegram.bot_token",
        "notifications.telegram.chat_id",
        "notifications.telegram.events.status",
        "notifications.telegram.events.signals",
        "notifications.telegram.events.positions",
        "notifications.telegram.events.trailing",
        "notifications.telegram.events.errors",
        "notifications.telegram.events.analysis"
      )
    end

    it "falls back to bot.yml symbols when no enabled SymbolConfig rows exist" do
      SymbolConfig.delete_all
      allow(described_class).to receive(:bot_yml_hash).and_return(
        "symbols" => [
          { "symbol" => "ETHUSD", "leverage" => 8 }
        ]
      )

      raw = described_class.runtime_raw

      expect(raw["symbols"]).to eq([{ "symbol" => "ETHUSD", "leverage" => 8 }])
    end

    it "prefers enabled SymbolConfig over bot.yml when both exist" do
      allow(described_class).to receive(:bot_yml_hash).and_return(
        "symbols" => [
          { "symbol" => "ETHUSD", "leverage" => 99 }
        ]
      )

      raw = described_class.runtime_raw

      expect(raw["symbols"].size).to eq(1)
      expect(raw["symbols"].first["symbol"]).to eq("BTCUSD")
      expect(raw["symbols"].first["leverage"]).to eq(10)
    end
  end

  let(:valid_yaml) do
    {
      "mode" => "testnet",
      "strategy" => {
        "supertrend" => { "atr_period" => 10, "multiplier" => 2.2 },
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
    expect(config.supertrend_multiplier).to eq(2.2)
    expect(config.supertrend_variant).to eq("classic")
    expect(config.effective_min_candles_for_supertrend).to eq(30)
  end

  context "with ml_adaptive supertrend" do
    let(:ml_yaml) do
      valid_yaml.deep_dup.tap do |y|
        y["strategy"] = y["strategy"].merge(
          "candles_lookback" => 150,
          "min_candles_required" => 120,
          "supertrend" => {
            "variant" => "ml_adaptive",
            "atr_period" => 10,
            "multiplier" => 2.0,
            "ml_adaptive" => { "training_period" => 100 }
          }
        )
      end
    end

    it "raises when candles_lookback is below training_period" do
      bad = ml_yaml.deep_dup
      bad["strategy"]["candles_lookback"] = 50
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /candles_lookback/)
    end

    it "exposes ml adaptive settings and effective min candles" do
      cfg = described_class.new(ml_yaml)
      expect(cfg.ml_adaptive_supertrend_training_period).to eq(100)
      expect(cfg.effective_min_candles_for_supertrend).to eq(120)
    end
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
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /watchlist must not be empty/)
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
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /watchlist must not be empty/)
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
