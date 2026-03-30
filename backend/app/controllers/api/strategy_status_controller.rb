# frozen_string_literal: true

module Api
  class StrategyStatusController < ApplicationController
    STRATEGY_KEY = "delta:strategy:state"

    TIMEFRAMES = [
      { tf: "1H",  role: "Trend filter",   indicator: "Supertrend direction" },
      { tf: "15M", role: "Confirmation",   indicator: "Supertrend + ADX strength" },
      { tf: "5M",  role: "Entry trigger",  indicator: "BOS + Order Block zone" }
    ].freeze

    def index
      bot_config = load_bot_config

      symbols = live_symbol_states(bot_config[:symbols])

      render json: {
        strategy: {
          name:        "Multi-Timeframe Confluence",
          description: "Supertrend + ADX across 3 timeframes. All must agree before entry.",
          mode:        bot_config[:mode],
          timeframes:  TIMEFRAMES,
          params: {
            atr_period:    bot_config.dig(:strategy, :atr_period),
            multiplier:    bot_config.dig(:strategy, :multiplier),
            adx_period:    bot_config.dig(:strategy, :adx_period),
            adx_threshold: bot_config.dig(:strategy, :adx_threshold),
            trail_pct:     bot_config.dig(:strategy, :trail_pct)
          },
          entry_rules: [
            "1H Supertrend must be bullish (long) or bearish (short)",
            "15M Supertrend must agree with 1H direction",
            "15M ADX ≥ #{bot_config.dig(:strategy, :adx_threshold)} (trending, not ranging)",
            "5M BOS confirmed in trend direction + fresh Order Block present",
            "MomentumFilter: RSI not extreme (not overbought for longs / oversold for shorts)",
            "VolumeFilter: CVD agrees with direction + price on correct side of VWAP",
            "DerivativesFilter: OI rising (no divergence) + funding rate within ±0.05%"
          ],
          exit_rules: [
            "#{bot_config.dig(:strategy, :trail_pct)}% trailing stop checked every 5 seconds",
            "Stop trails peak price; exit when price retraces past stop"
          ]
        },
        symbols: symbols
      }
    end

    private

    def live_symbol_states(configured_symbols)
      redis = Redis.new
      raw   = redis.hgetall(STRATEGY_KEY)

      configured_symbols.map do |sym|
        state = raw[sym] ? JSON.parse(raw[sym], symbolize_names: true) : {}
        { symbol: sym }.merge(state)
      end
    rescue Redis::BaseError
      configured_symbols.map { |s| { symbol: s } }
    end

    def load_bot_config
      path = Rails.root.join("config", "bot.yml")
      return default_config unless path.exist?

      raw = YAML.safe_load(path.read, permitted_classes: [], aliases: true)
      {
        mode:    raw["mode"],
        symbols: (raw["symbols"] || []).map { |s| s["symbol"] },
        strategy: {
          atr_period:    raw.dig("strategy", "supertrend", "atr_period"),
          multiplier:    raw.dig("strategy", "supertrend", "multiplier"),
          adx_period:    raw.dig("strategy", "adx", "period"),
          adx_threshold: raw.dig("strategy", "adx", "threshold"),
          trail_pct:     raw.dig("strategy", "trailing_stop_pct")
        }
      }
    rescue StandardError
      default_config
    end

    def default_config
      {
        mode: "unknown", symbols: %w[BTCUSD ETHUSD SOLUSD],
        strategy: { atr_period: 10, multiplier: 3.0, adx_period: 14, adx_threshold: 20, trail_pct: 0.2 }
      }
    end
  end
end
