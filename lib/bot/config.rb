# frozen_string_literal: true

require "yaml"

module Bot
  class Config
    class ValidationError < StandardError; end

    VALID_MODES      = %w[dry_run testnet live].freeze
    VALID_LOG_LEVELS = %w[debug info warn error].freeze

    def initialize(raw)
      @raw = raw
      validate!
    end

    def self.load(path = File.expand_path("../../config/bot.yml", __dir__))
      raw = YAML.safe_load(File.read(path), permitted_classes: [], aliases: true)
      mode_override = ENV["BOT_MODE"]
      raw["mode"] = mode_override if mode_override && !mode_override.empty?
      new(raw)
    end

    def mode               = @raw["mode"]
    def dry_run?           = mode == "dry_run"
    def testnet?           = mode == "testnet"
    def live?              = mode == "live"

    def symbols
      @symbols ||= (@raw["symbols"] || []).map { |s| { symbol: s["symbol"], leverage: s["leverage"] } }
    end

    def symbol_names       = symbols.map { |s| s[:symbol] }

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

    def rsi_period
      @raw.dig("strategy", "rsi", "period")&.to_i || 14
    end

    def rsi_overbought
      @raw.dig("strategy", "rsi", "overbought")&.to_f || 70.0
    end

    def rsi_oversold
      @raw.dig("strategy", "rsi", "oversold")&.to_f || 30.0
    end

    def vwap_session_reset_hour_utc
      @raw.dig("strategy", "vwap", "session_reset_hour_utc")&.to_i || 0
    end

    def bos_swing_lookback
      @raw.dig("strategy", "bos", "swing_lookback")&.to_i || 10
    end

    def ob_min_impulse_pct
      @raw.dig("strategy", "order_block", "min_impulse_pct")&.to_f || 0.3
    end

    def ob_max_age
      @raw.dig("strategy", "order_block", "max_ob_age")&.to_i || 20
    end

    def funding_rate_threshold
      @raw.dig("strategy", "filters", "funding_rate_threshold")&.to_f || 0.05
    end

    def cvd_window
      @raw.dig("strategy", "filters", "cvd_window")&.to_i || 50
    end

    def oi_poll_interval
      @raw.dig("strategy", "derivatives", "oi_poll_interval")&.to_i || 30
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

    def paper_capital_inr
      val = @raw.dig("risk", "paper_capital_inr")
      val&.to_f
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

      error("symbols must not be empty") if symbols.empty?
      symbols.each do |s|
        error("symbol name must not be blank") if s[:symbol].to_s.strip.empty?
        error("leverage for #{s[:symbol]} must be 1–200") unless s[:leverage].between?(1, 200)
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
