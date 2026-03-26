# frozen_string_literal: true

require_relative "adx"
require_relative "supertrend"
require "redis"

module Bot
  module Strategy
    class MultiTimeframe
      def initialize(config:, market_data:, logger:)
        @config      = config
        @market_data = market_data
        @logger      = logger
        @last_acted  = {}  # symbol → candle_ts of last acted-on entry candle
        @redis       = Redis.new
      end

      # Returns a Signal or nil
      def evaluate(symbol, current_price:)
        h1_candles  = fetch_candles(symbol, @config.timeframe_trend)
        m15_candles = fetch_candles(symbol, @config.timeframe_confirm)
        m5_candles  = fetch_candles(symbol, @config.timeframe_entry)

        return nil unless sufficient?(h1_candles, symbol, "1H") &&
                          sufficient?(m15_candles, symbol, "15M") &&
                          sufficient?(m5_candles, symbol, "5M")

        h1_st   = Supertrend.compute(h1_candles,  atr_period: @config.supertrend_atr_period, multiplier: @config.supertrend_multiplier)
        m15_st  = Supertrend.compute(m15_candles, atr_period: @config.supertrend_atr_period, multiplier: @config.supertrend_multiplier)
        m15_adx = ADX.compute(m15_candles, period: @config.adx_period)
        m5_st   = Supertrend.compute(m5_candles,  atr_period: @config.supertrend_atr_period, multiplier: @config.supertrend_multiplier)

        h1_dir       = h1_st.last[:direction]
        m15_dir      = m15_st.last[:direction]
        m15_adx_val  = m15_adx.last[:adx]
        m5_prev_dir  = m5_st[-2]&.dig(:direction)
        m5_last_dir  = m5_st.last[:direction]
        m5_last_ts   = m5_candles.last[:timestamp].to_i

        persist_symbol_state(symbol, {
          h1_dir: h1_dir,
          m15_dir: m15_dir,
          m5_dir: m5_last_dir,
          adx: m15_adx_val,
          updated_at: Time.current.iso8601
        })

        if h1_dir.nil? || m15_dir.nil? || m5_last_dir.nil?
          @logger.debug("strategy_skip", symbol: symbol, reason: "nil_direction",
                        h1: h1_dir, m15: m15_dir, m5: m5_last_dir)
          return nil
        end

        if m15_adx_val.nil? || m15_adx_val < @config.adx_threshold
          @logger.debug("strategy_skip", symbol: symbol, reason: "adx_below_threshold",
                        adx: m15_adx_val&.round(2), threshold: @config.adx_threshold)
          return nil
        end

        # Check for fresh flip on 5M — previous direction must differ from current
        just_flipped = m5_prev_dir && m5_last_dir != m5_prev_dir

        # In dry_run the flip requirement is relaxed so test signals fire on directional
        # alignment alone — in testnet/live a genuine 5M flip is required.
        unless just_flipped || @config.dry_run?
          @logger.debug("strategy_skip", symbol: symbol, reason: "no_5m_flip",
                        m5_prev: m5_prev_dir, m5_last: m5_last_dir,
                        h1: h1_dir, m15: m15_dir, adx: m15_adx_val&.round(2))
          return nil
        end

        if @last_acted[symbol] == m5_last_ts
          @logger.debug("strategy_skip", symbol: symbol, reason: "stale_candle", candle_ts: m5_last_ts)
          return nil
        end

        side = if h1_dir == :bullish && m15_dir == :bullish && m5_last_dir == :bullish
                 :long
               elsif h1_dir == :bearish && m15_dir == :bearish && m5_last_dir == :bearish
                 :short
               end

        unless side
          @logger.debug("strategy_skip", symbol: symbol, reason: "no_confluence",
                        h1: h1_dir, m15: m15_dir, m5: m5_last_dir)
          return nil
        end

        @last_acted[symbol] = m5_last_ts
        @logger.info("signal_generated", symbol: symbol, side: side, candle_ts: m5_last_ts)

        Signal.new(symbol: symbol, side: side, entry_price: current_price, candle_ts: m5_last_ts)
      end

      private

      def fetch_candles(symbol, resolution)
        end_ts   = Time.now.to_i
        start_ts = end_ts - (resolution_to_seconds(resolution) * @config.candles_lookback)

        raw = @market_data.candles({
          "symbol"     => symbol,
          "resolution" => resolution,
          "start"      => start_ts,
          "end"        => end_ts
        })

        # Handle nested result array if present
        candles_payload = if raw.is_a?(Hash) && raw.key?("result")
                           raw["result"]
                         elsif raw.is_a?(Hash) && raw.key?(:result)
                           raw[:result]
                         else
                           raw
                         end

        return [] unless candles_payload.is_a?(Array)

        candles_payload.map do |c|
          { open:      (c[:open]      || c["open"])&.to_f      || raise("missing open in candle"),
            high:      (c[:high]      || c["high"])&.to_f      || raise("missing high in candle"),
            low:       (c[:low]       || c["low"])&.to_f       || raise("missing low in candle"),
            close:     (c[:close]     || c["close"])&.to_f     || raise("missing close in candle"),
            timestamp: (c[:timestamp] || c["timestamp"] || c[:time] || c["time"])&.to_i || raise("missing timestamp in candle") }
        end.sort_by { |c| c[:timestamp] }
      rescue StandardError => e
        @logger.error("candle_fetch_failed", symbol: symbol, resolution: resolution, message: e.message)
        []
      end

      def sufficient?(candles, symbol, label)
        if candles.size < @config.min_candles_required
          @logger.warn("insufficient_candles", symbol: symbol, timeframe: label, count: candles.size)
          return false
        end
        true
      end

      def resolution_to_seconds(resolution)
        match = resolution.match(/(\d+)([smhdw])/)
        return resolution.to_i * 60 unless match # fallback for backward compatibility

        value = match[1].to_i
        unit  = match[2]
        case unit
        when "s" then value
        when "m" then value * 60
        when "h" then value * 3600
        when "d" then value * 86400
        when "w" then value * 604800
        else value * 60
        end
      end

      def persist_symbol_state(symbol, data)
        # Using the same key as the StrategyStatusController
        @redis.hset("delta:strategy:state", symbol, data.to_json)
      rescue StandardError => e
        @logger.error("strategy_persistence_failed", symbol: symbol, message: e.message)
      end
    end
  end
end
