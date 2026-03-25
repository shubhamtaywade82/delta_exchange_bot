# frozen_string_literal: true

require "yaml"

module Bot
  class Config
    class ValidationError < StandardError; end

    VALID_MODES = %w[dry_run testnet live].freeze

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

    def mode               = @raw.fetch("mode")
    def dry_run?           = mode == "dry_run"
    def testnet?           = mode == "testnet"
    def live?              = mode == "live"

    def symbols
      @raw["symbols"].map { |s| { symbol: s["symbol"], leverage: s["leverage"] } }
    end

    def symbol_names       = symbols.map { |s| s[:symbol] }

    def leverage_for(symbol)
      entry = symbols.find { |s| s[:symbol] == symbol }
      raise ArgumentError, "Unknown symbol: #{symbol}" unless entry
      entry[:leverage]
    end

    def supertrend_atr_period  = @raw.dig("strategy", "supertrend", "atr_period").to_i
    def supertrend_multiplier  = @raw.dig("strategy", "supertrend", "multiplier").to_f
    def adx_period             = @raw.dig("strategy", "adx", "period").to_i
    def adx_threshold          = @raw.dig("strategy", "adx", "threshold").to_f
    def trailing_stop_pct      = @raw.dig("strategy", "trailing_stop_pct").to_f
    def timeframe_trend        = @raw.dig("strategy", "timeframes", "trend")
    def timeframe_confirm      = @raw.dig("strategy", "timeframes", "confirm")
    def timeframe_entry        = @raw.dig("strategy", "timeframes", "entry")
    def candles_lookback       = @raw.dig("strategy", "candles_lookback").to_i
    def min_candles_required   = @raw.dig("strategy", "min_candles_required").to_i

    def risk_per_trade_pct           = @raw.dig("risk", "risk_per_trade_pct").to_f
    def max_concurrent_positions     = @raw.dig("risk", "max_concurrent_positions").to_i
    def max_margin_per_position_pct  = @raw.dig("risk", "max_margin_per_position_pct").to_f
    def usd_to_inr_rate              = @raw.dig("risk", "usd_to_inr_rate").to_f

    def telegram_enabled?  = @raw.dig("notifications", "telegram", "enabled") == true
    def telegram_token     = @raw.dig("notifications", "telegram", "bot_token")
    def telegram_chat_id   = @raw.dig("notifications", "telegram", "chat_id").to_s
    def daily_summary_time = @raw.dig("notifications", "daily_summary_time")

    def log_level  = @raw.dig("logging", "level") || "info"
    def log_file   = @raw.dig("logging", "file") || "logs/bot.log"

    private

    def validate!
      error("mode must be one of: #{VALID_MODES.join(', ')}") unless VALID_MODES.include?(mode)
      error("symbols must not be empty") if symbols.empty?
      error("risk_per_trade_pct must be between 0.1 and 10") unless risk_per_trade_pct.between?(0.1, 10.0)
      error("max_concurrent_positions must be 1–20") unless max_concurrent_positions.between?(1, 20)
      error("trailing_stop_pct must be 0.1–20") unless trailing_stop_pct.between?(0.1, 20.0)
      error("supertrend.atr_period must be 1–50") unless supertrend_atr_period.between?(1, 50)
      error("supertrend.multiplier must be 0.5–10") unless supertrend_multiplier.between?(0.5, 10.0)
      error("adx.period must be 1–50") unless adx_period.between?(1, 50)
      error("adx.threshold must be 10–50") unless adx_threshold.between?(10, 50)
      error("usd_to_inr_rate must be > 0") unless usd_to_inr_rate.positive?
      symbols.each do |s|
        error("leverage for #{s[:symbol]} must be 1–200") unless s[:leverage].between?(1, 200)
      end
    end

    def error(msg)
      raise ValidationError, "Config error: #{msg}"
    end
  end
end
