# frozen_string_literal: true

# Describes how each runtime +Setting+ key should be edited in the admin UI (widget + options).
class RuntimeSettingUi
  TIMEFRAMES = %w[1m 3m 5m 15m 30m 1h 2h 4h 1d].freeze

  INDICATOR_TYPES = (
    Bot::Config::ML_ADAPTIVE_SUPERTREND_TYPE_ALIASES.map(&:to_s).uniq + %w[supertrend]
  ).freeze

  class << self
    def payload_for(key, value_type:)
      vt = (value_type.presence || "string").to_s
      return toggle_payload if vt == "boolean"
      return secret_payload if secret_key?(key)

      specific = registry[key]
      return deep_stringify(specific) if specific

      number_fallback(vt)
    end

    private

    def deep_stringify(obj)
      case obj
      when Hash then obj.transform_values { |v| deep_stringify(v) }
      when Array then obj.map { |e| e.is_a?(Hash) ? deep_stringify(e) : e }
      else obj
      end
    end

    def secret_key?(key)
      k = key.to_s.downcase
      k.include?("api_key") || k.include?("bot_token") || k.end_with?("_key") || k.include?("secret")
    end

    def toggle_payload
      { "widget" => "toggle" }
    end

    def secret_payload
      { "widget" => "password" }
    end

    def select_options(values)
      values.map { |v| { "value" => v, "label" => v } }
    end

    def timeframe_options
      select_options(TIMEFRAMES)
    end

    def registry
      @registry ||= build_registry
    end

    def build_registry
      {
        "bot.mode" => {
          "widget" => "select",
          "options" => select_options(Bot::Config::VALID_MODES)
        },
        "logging.level" => {
          "widget" => "select",
          "options" => select_options(Bot::Config::VALID_LOG_LEVELS)
        },
        "strategy.supertrend.variant" => {
          "widget" => "select",
          "options" => select_options(Bot::Config::VALID_SUPERTREND_VARIANTS)
        },
        "strategy.supertrend.indicator_type" => {
          "widget" => "select",
          "options" => select_options(INDICATOR_TYPES.sort)
        },
        "strategy.supertrend.type" => {
          "widget" => "select",
          "options" => select_options(INDICATOR_TYPES.sort)
        },
        "strategy.timeframes.trend" => { "widget" => "select", "options" => timeframe_options },
        "strategy.timeframes.confirm" => { "widget" => "select", "options" => timeframe_options },
        "strategy.timeframes.entry" => { "widget" => "select", "options" => timeframe_options },
        "learning.epsilon" => number_field("float", min: 0, max: 1, step: 0.005),
        "regime.imbalance_threshold" => number_field("float", min: 0, max: 1, step: 0.05),
        "regime.spread_threshold" => number_field("float", min: 0, max: 100, step: 0.1),
        "regime.volatility_threshold" => number_field("float", min: 0, max: 500, step: 1),
        "risk.risk_per_trade_pct" => number_field("float", min: 0.1, max: 10, step: 0.1),
        "risk.daily_loss_cap_pct" => number_field("float", min: 0.01, max: 1, step: 0.01),
        "risk.max_concurrent_positions" => number_field("integer", min: 1, max: 20, step: 1),
        "risk.max_margin_per_position_pct" => number_field("float", min: 5, max: 100, step: 0.5),
        "risk.max_margin_utilization" => number_field("float", min: 0.05, max: 1, step: 0.05),
        "risk.usd_to_inr_rate" => number_field("float", min: 1, max: 200, step: 0.5),
        "risk.simulated_capital_inr" => number_field("float", min: 1000, max: 10_000_000, step: 1000),
        "strategy.trailing_stop_pct" => number_field("float", min: 0.1, max: 20, step: 0.1),
        "strategy.adx.period" => number_field("integer", min: 1, max: 50, step: 1),
        "strategy.adx.threshold" => number_field("float", min: 10, max: 50, step: 0.5),
        "strategy.candles_lookback" => number_field("integer", min: 20, max: 2000, step: 10),
        "strategy.min_candles_required" => number_field("integer", min: 5, max: 1000, step: 1),
        "strategy.supertrend.atr_period" => number_field("integer", min: 1, max: 50, step: 1),
        "strategy.supertrend.multiplier" => number_field("float", min: 0.5, max: 10, step: 0.1),
        "strategy.supertrend.ml_adaptive.training_period" => number_field("integer", min: 10, max: 500, step: 10),
        "strategy.supertrend.ml_adaptive.highvol" => number_field("float", min: 0.01, max: 0.99, step: 0.01),
        "strategy.supertrend.ml_adaptive.midvol" => number_field("float", min: 0.01, max: 0.99, step: 0.01),
        "strategy.supertrend.ml_adaptive.lowvol" => number_field("float", min: 0.01, max: 0.99, step: 0.01),
        "runner.strategy_interval_seconds" => number_field("integer", min: 5, max: 600, step: 5),
        "runner.strategy_symbol_stagger_seconds" => number_field("float", min: 0, max: 60, step: 0.5),
        "ai.config_cache_seconds" => number_field("integer", min: 0, max: 86_400, step: 1),
        "ai.ollama_max_retries" => number_field("integer", min: 0, max: 10, step: 1),
        "ai.ollama_timeout_seconds" => number_field("integer", min: 1, max: 300, step: 1),
        "ai.ollama_model" => {
          "widget" => "select",
          "options" => select_options(%w[llama3 llama3.1 llama3.2 mistral codellama phi3])
        }
      }
    end

    def number_field(value_kind, min:, max:, step:)
      {
        "widget" => "number",
        "value_kind" => value_kind,
        "min" => min,
        "max" => max,
        "step" => step
      }
    end

    def number_fallback(value_type)
      case value_type
      when "integer"
        { "widget" => "number", "value_kind" => "integer", "min" => nil, "max" => nil, "step" => 1 }
      when "float"
        { "widget" => "number", "value_kind" => "float", "min" => nil, "max" => nil, "step" => "any" }
      else
        { "widget" => "text" }
      end
    end
  end
end
