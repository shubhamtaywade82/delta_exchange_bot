# frozen_string_literal: true

module Bot
  class Config
    class ValidationError < StandardError; end

    VALID_MODES               = %w[dry_run testnet live].freeze
    VALID_LOG_LEVELS          = %w[debug info warn error].freeze
    VALID_SUPERTREND_VARIANTS = %w[classic ml_adaptive].freeze
    ML_ADAPTIVE_SUPERTREND_TYPE_ALIASES = %w[ml_adaptive_supertrend mast ml_st ml_adaptive].freeze

    def initialize(raw)
      @raw = raw
      validate!
    end

    DEFAULTS = {
      "mode" => "dry_run",
      "strategy" => {
        "supertrend" => {
          "variant" => "classic",
          "atr_period" => 10,
          "multiplier" => 3.0,
          "ml_adaptive" => {
            "training_period" => 100,
            "highvol" => 0.75,
            "midvol" => 0.5,
            "lowvol" => 0.25
          }
        },
        "adx" => { "period" => 14, "threshold" => 20 },
        "filters" => { "relax_in_dry_run" => true },
        "trailing_stop_pct" => 0.2,
        "timeframes" => { "trend" => "1h", "confirm" => "15m", "entry" => "5m" },
        "candles_lookback" => 100,
        "min_candles_required" => 30
      },
      "risk" => {
        "risk_per_trade_pct" => 1.5,
        "max_concurrent_positions" => 5,
        "max_margin_per_position_pct" => 40.0,
        "usd_to_inr_rate" => 85.0,
        "simulated_capital_inr" => 10_000.0
      },
      "notifications" => {
        "telegram" => { "enabled" => false, "bot_token" => "", "chat_id" => "" },
        "daily_summary_time" => "18:00"
      },
      "logging" => { "level" => "info", "file" => "logs/bot.log" }
    }.freeze

    def self.load(_path = nil)
      raw = runtime_raw
      mode_override = ENV["BOT_MODE"]
      raw["mode"] = mode_override if mode_override && !mode_override.empty?
      new(raw)
    end

    def self.runtime_raw
      raw = Marshal.load(Marshal.dump(DEFAULTS))

      apply_setting!(raw, "mode", key: "bot.mode")
      apply_setting!(raw, "strategy", "supertrend", "variant", key: "strategy.supertrend.variant")
      apply_setting!(raw, "strategy", "supertrend", "type", key: "strategy.supertrend.type")
      apply_setting!(raw, "strategy", "supertrend", "indicator_type", key: "strategy.supertrend.indicator_type")
      apply_setting!(raw, "strategy", "supertrend", "atr_period", key: "strategy.supertrend.atr_period")
      apply_setting!(raw, "strategy", "supertrend", "multiplier", key: "strategy.supertrend.multiplier")
      apply_setting!(raw, "strategy", "supertrend", "ml_adaptive", "training_period", key: "strategy.supertrend.ml_adaptive.training_period")
      apply_setting!(raw, "strategy", "supertrend", "ml_adaptive", "highvol", key: "strategy.supertrend.ml_adaptive.highvol")
      apply_setting!(raw, "strategy", "supertrend", "ml_adaptive", "midvol", key: "strategy.supertrend.ml_adaptive.midvol")
      apply_setting!(raw, "strategy", "supertrend", "ml_adaptive", "lowvol", key: "strategy.supertrend.ml_adaptive.lowvol")
      apply_setting!(raw, "strategy", "adx", "period", key: "strategy.adx.period")
      apply_setting!(raw, "strategy", "adx", "threshold", key: "strategy.adx.threshold")
      apply_setting!(raw, "strategy", "filters", "relax_in_dry_run", key: "strategy.filters.relax_in_dry_run")
      apply_setting!(raw, "strategy", "trailing_stop_pct", key: "strategy.trailing_stop_pct")
      apply_setting!(raw, "strategy", "timeframes", "trend", key: "strategy.timeframes.trend")
      apply_setting!(raw, "strategy", "timeframes", "confirm", key: "strategy.timeframes.confirm")
      apply_setting!(raw, "strategy", "timeframes", "entry", key: "strategy.timeframes.entry")
      apply_setting!(raw, "strategy", "candles_lookback", key: "strategy.candles_lookback")
      apply_setting!(raw, "strategy", "min_candles_required", key: "strategy.min_candles_required")
      apply_setting!(raw, "risk", "risk_per_trade_pct", key: "risk.risk_per_trade_pct")
      apply_setting!(raw, "risk", "max_concurrent_positions", key: "risk.max_concurrent_positions")
      apply_setting!(raw, "risk", "max_margin_per_position_pct", key: "risk.max_margin_per_position_pct")
      apply_setting!(raw, "risk", "usd_to_inr_rate", key: "risk.usd_to_inr_rate")
      apply_setting!(raw, "risk", "simulated_capital_inr", key: "risk.simulated_capital_inr")
      apply_setting!(raw, "notifications", "telegram", "enabled", key: "notifications.telegram.enabled")
      apply_setting!(raw, "notifications", "telegram", "bot_token", key: "notifications.telegram.bot_token")
      apply_setting!(raw, "notifications", "telegram", "chat_id", key: "notifications.telegram.chat_id")
      apply_setting!(raw, "notifications", "daily_summary_time", key: "notifications.daily_summary_time")
      apply_setting!(raw, "logging", "level", key: "logging.level")
      apply_setting!(raw, "logging", "file", key: "logging.file")

      raw["symbols"] = SymbolConfig.where(enabled: true).order(:symbol).map do |symbol|
        { "symbol" => symbol.symbol, "leverage" => symbol.leverage }
      end

      raw
    end

    def self.apply_setting!(raw, *path, key:)
      setting = Setting.find_by(key: key)
      return if setting.nil?

      leaf_key = path.pop
      container = raw
      path.each { |segment| container = container[segment] ||= {} }
      container[leaf_key] = setting.typed_value
    end

    def mode               = @raw["mode"]
    def dry_run?           = mode == "dry_run"
    def testnet?           = mode == "testnet"
    def live?              = mode == "live"

    def symbols
      @symbols ||= begin
        db_symbols = SymbolConfig.where(enabled: true).map { |s| { symbol: s.symbol, leverage: s.leverage } }
        if db_symbols.any?
          db_symbols
        else
          (@raw["symbols"] || []).map { |s| { symbol: s["symbol"], leverage: s["leverage"] } }
        end
      end
    end

    def symbol_names = symbols.map { |s| s[:symbol] }

    def leverage_for(symbol)
      entry = symbols.find { |s| s[:symbol] == symbol }
      raise ArgumentError, "Unknown symbol: #{symbol}" unless entry
      entry[:leverage]
    end

    def supertrend_atr_period
      val = @raw.dig("strategy", "supertrend", "atr_period")
      error("strategy.supertrend.atr_period is required") if val.nil?
      val.to_i
    end

    def supertrend_multiplier
      val = @raw.dig("strategy", "supertrend", "multiplier")
      error("strategy.supertrend.multiplier is required") if val.nil?
      val.to_f
    end

    # classic | ml_adaptive — selects Bot::Strategy::IndicatorFactory Supertrend backend
    def supertrend_variant
      v = @raw.dig("strategy", "supertrend", "variant")
      return "classic" if v.nil? || v.to_s.strip.empty?

      v.to_s.downcase
    end

    # Optional, algo_scalper-style alias: mast, ml_st, ml_adaptive_supertrend, …
    def supertrend_indicator_type
      t = @raw.dig("strategy", "supertrend", "indicator_type") ||
          @raw.dig("strategy", "supertrend", "type")
      t.nil? || t.to_s.strip.empty? ? "supertrend" : t.to_s
    end

    def ml_adaptive_supertrend_training_period
      (@raw.dig("strategy", "supertrend", "ml_adaptive", "training_period") || 100).to_i
    end

    def ml_adaptive_supertrend_highvol
      (@raw.dig("strategy", "supertrend", "ml_adaptive", "highvol") || 0.75).to_f
    end

    def ml_adaptive_supertrend_midvol
      (@raw.dig("strategy", "supertrend", "ml_adaptive", "midvol") || 0.5).to_f
    end

    def ml_adaptive_supertrend_lowvol
      (@raw.dig("strategy", "supertrend", "ml_adaptive", "lowvol") || 0.25).to_f
    end

    def effective_min_candles_for_supertrend
      return min_candles_required unless uses_ml_adaptive_supertrend?

      [
        min_candles_required,
        ml_adaptive_supertrend_training_period,
        supertrend_atr_period
      ].max
    end

    def uses_ml_adaptive_supertrend?
      ML_ADAPTIVE_SUPERTREND_TYPE_ALIASES.include?(supertrend_indicator_type.to_s.downcase) ||
        supertrend_variant == "ml_adaptive"
    end

    def adx_period
      val = @raw.dig("strategy", "adx", "period")
      error("strategy.adx.period is required") if val.nil?
      val.to_i
    end

    def adx_threshold
      val = @raw.dig("strategy", "adx", "threshold")
      error("strategy.adx.threshold is required") if val.nil?
      val.to_f
    end

    def relax_filters_in_dry_run?
      val = @raw.dig("strategy", "filters", "relax_in_dry_run")
      return true if val.nil?

      val == true
    end

    def trailing_stop_pct
      val = @raw.dig("strategy", "trailing_stop_pct")
      error("strategy.trailing_stop_pct is required") if val.nil?
      val.to_f
    end

    def timeframe_trend        = @raw.dig("strategy", "timeframes", "trend")
    def timeframe_confirm      = @raw.dig("strategy", "timeframes", "confirm")
    def timeframe_entry        = @raw.dig("strategy", "timeframes", "entry")

    def candles_lookback
      val = @raw.dig("strategy", "candles_lookback")
      error("strategy.candles_lookback is required") if val.nil?
      val.to_i
    end

    def min_candles_required
      val = @raw.dig("strategy", "min_candles_required")
      error("strategy.min_candles_required is required") if val.nil?
      val.to_i
    end

    def risk_per_trade_pct
      val = @raw.dig("risk", "risk_per_trade_pct")
      error("risk.risk_per_trade_pct is required") if val.nil?
      val.to_f
    end

    def max_concurrent_positions
      val = @raw.dig("risk", "max_concurrent_positions")
      error("risk.max_concurrent_positions is required") if val.nil?
      val.to_i
    end

    def max_margin_per_position_pct
      val = @raw.dig("risk", "max_margin_per_position_pct")
      error("risk.max_margin_per_position_pct is required") if val.nil?
      val.to_f
    end

    def usd_to_inr_rate
      val = @raw.dig("risk", "usd_to_inr_rate")
      error("risk.usd_to_inr_rate is required") if val.nil?
      val.to_f
    end

    def simulated_capital_inr
      @raw.dig("risk", "simulated_capital_inr")&.to_f || 10_000.0
    end

    def telegram_enabled?  = @raw.dig("notifications", "telegram", "enabled") == true
    def telegram_token     = @raw.dig("notifications", "telegram", "bot_token")
    def telegram_chat_id   = @raw.dig("notifications", "telegram", "chat_id").to_s
    def daily_summary_time = @raw.dig("notifications", "daily_summary_time")

    def log_level  = @raw.dig("logging", "level") || "info"
    def log_file   = @raw.dig("logging", "file") || "logs/bot.log"

    private

    def validate!
      error("mode is required") if mode.nil?
      error("mode must be one of: #{VALID_MODES.join(', ')}") unless VALID_MODES.include?(mode)

      # Skip validation for symbols if they are already in the DB and validated there
      # But we still check names and leverage ranges for safety
      if symbols.empty?
        error("watchlist must not be empty (add symbols via UI or bot.yml)")
      end
      
      symbols.each do |s|
        error("symbol name must not be blank") if s[:symbol].to_s.strip.empty?
        error("leverage for #{s[:symbol]} must be 1–200") unless s[:leverage].to_i.between?(1, 200)
      end

      error("risk_per_trade_pct must be between 0.1 and 10") unless risk_per_trade_pct.between?(0.1, 10.0)
      error("max_concurrent_positions must be 1–20") unless max_concurrent_positions.between?(1, 20)
      error("max_margin_per_position_pct must be between 5.0 and 100.0") unless max_margin_per_position_pct.between?(5.0, 100.0)
      error("trailing_stop_pct must be 0.1–20") unless trailing_stop_pct.between?(0.1, 20.0)
      error("supertrend.atr_period must be 1–50") unless supertrend_atr_period.between?(1, 50)
      error("supertrend.multiplier must be 0.5–10") unless supertrend_multiplier.between?(0.5, 10.0)
      error("adx.period must be 1–50") unless adx_period.between?(1, 50)
      error("adx.threshold must be 10–50") unless adx_threshold.between?(10, 50)
      error("usd_to_inr_rate must be > 0") unless usd_to_inr_rate.positive?

      error("min_candles_required must be <= candles_lookback") if min_candles_required > candles_lookback

      unless VALID_SUPERTREND_VARIANTS.include?(supertrend_variant)
        error("supertrend.variant must be one of: #{VALID_SUPERTREND_VARIANTS.join(', ')}")
      end

      if uses_ml_adaptive_supertrend?
        error("ml_adaptive.training_period must be 10–500") unless ml_adaptive_supertrend_training_period.between?(10, 500)
        error("candles_lookback must be >= ml_adaptive.training_period") if candles_lookback < ml_adaptive_supertrend_training_period
        h, m, l = ml_adaptive_supertrend_highvol, ml_adaptive_supertrend_midvol, ml_adaptive_supertrend_lowvol
        error("supertrend.ml_adaptive vol percentiles must satisfy highvol > midvol > lowvol") unless h > m && m > l
        error("supertrend.ml_adaptive percentile bounds must be in (0,1)") unless h.between?(0.01, 0.99) && m.between?(0.01, 0.99) && l.between?(0.01, 0.99)
      end

      if telegram_enabled?
        error("telegram.bot_token must not be blank when telegram is enabled") if telegram_token.to_s.strip.empty?
        error("telegram.chat_id must not be blank when telegram is enabled") if telegram_chat_id.to_s.strip.empty?
      end

      if daily_summary_time && !/\A([01]\d|2[0-3]):[0-5]\d\z/.match?(daily_summary_time)
        error("daily_summary_time must be in HH:MM format")
      end

      error("log_level must be one of: #{VALID_LOG_LEVELS.join(', ')}") unless VALID_LOG_LEVELS.include?(log_level)
    end

    def error(msg)
      raise ValidationError, "Config error: #{msg}"
    end
  end
end
