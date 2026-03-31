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
      config = Bot::Config.load
      {
        mode:    config.mode,
        symbols: config.symbol_names,
        strategy: {
          atr_period:    config.supertrend_atr_period,
          multiplier:    config.supertrend_multiplier,
          supertrend_variant: config.supertrend_variant,
          supertrend_indicator_type: config.supertrend_indicator_type,
          ml_adaptive: {
            training_period: config.ml_adaptive_supertrend_training_period,
            highvol: config.ml_adaptive_supertrend_highvol,
            midvol: config.ml_adaptive_supertrend_midvol,
            lowvol: config.ml_adaptive_supertrend_lowvol
          },
          adx_period:    config.adx_period,
          adx_threshold: config.adx_threshold,
          trail_pct:     config.trailing_stop_pct
        }
      }
    rescue Bot::Config::ValidationError, StandardError
      default_config
    end

    def default_config
      {
        mode: "unknown", symbols: %w[BTCUSD ETHUSD SOLUSD],
        strategy: {
          atr_period: 10, multiplier: 3.0, supertrend_variant: "classic",
          supertrend_indicator_type: nil, ml_adaptive: nil,
          adx_period: 14, adx_threshold: 20, trail_pct: 0.2
        }
      }
    end
  end
end
