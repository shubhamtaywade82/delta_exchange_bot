# frozen_string_literal: true

module Api
  class StrategyStatusController < ApplicationController
    STRATEGY_KEY = "delta:strategy:state"

    def index
      bot_config = load_bot_config

      symbols = live_symbol_states(bot_config[:symbols])
      st_line   = supertrend_indicator_label(bot_config)
      strat     = bot_config[:strategy]
      timeframes = [
        { tf: timeframe_display(strat[:timeframe_trend]),   role: "Trend filter",
          indicator: "#{st_line} direction" },
        { tf: timeframe_display(strat[:timeframe_confirm]), role: "Confirmation",
          indicator: "#{st_line} + ADX strength" },
        { tf: timeframe_display(strat[:timeframe_entry]),   role: "Entry trigger",
          indicator: "BOS + Order Block zone" }
      ]

      render json: {
        strategy: {
          name:        "Multi-Timeframe Confluence",
          description: "#{st_line} + ADX across 3 timeframes. All must agree before entry.",
          mode:        bot_config[:mode],
          timeframes:  timeframes,
          params: {
            supertrend_variant: bot_config.dig(:strategy, :supertrend_variant),
            atr_period:    bot_config.dig(:strategy, :atr_period),
            multiplier:    bot_config.dig(:strategy, :multiplier),
            ml_adaptive:   bot_config.dig(:strategy, :ml_adaptive),
            adx_period:    bot_config.dig(:strategy, :adx_period),
            adx_threshold: bot_config.dig(:strategy, :adx_threshold),
            trail_pct:     bot_config.dig(:strategy, :trail_pct)
          },
          entry_rules: [
            "#{timeframe_display(strat[:timeframe_trend])} #{st_line} must be bullish (long) or bearish (short)",
            "#{timeframe_display(strat[:timeframe_confirm])} #{st_line} must agree with trend direction",
            "#{timeframe_display(strat[:timeframe_confirm])} ADX ≥ #{bot_config.dig(:strategy, :adx_threshold)} (trending, not ranging)",
            "#{timeframe_display(strat[:timeframe_entry])} BOS confirmed in trend direction + fresh Order Block present",
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
          timeframe_trend: config.timeframe_trend,
          timeframe_confirm: config.timeframe_confirm,
          timeframe_entry: config.timeframe_entry,
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
          timeframe_trend: "1h", timeframe_confirm: "15m", timeframe_entry: "1m",
          atr_period: 10, multiplier: 2.2, supertrend_variant: "ml_adaptive",
          supertrend_indicator_type: nil,
          ml_adaptive: {
            training_period: 100, highvol: 0.75, midvol: 0.5, lowvol: 0.25
          },
          adx_period: 14, adx_threshold: 20, trail_pct: 0.2
        }
      }
    end

    def supertrend_indicator_label(bot_config)
      variant = bot_config.dig(:strategy, :supertrend_variant).to_s
      return "ML Adaptive Supertrend" if variant == "ml_adaptive"

      "Supertrend"
    end

    def timeframe_display(resolution)
      resolution.to_s.strip.downcase.sub(/([smhdw])$/) { |u| u.upcase }
    end
  end
end
