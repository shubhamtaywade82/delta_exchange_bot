# frozen_string_literal: true

require_relative "supertrend"
require_relative "adx"
require_relative "signal"

module Bot
  module Strategy
    class MultiTimeframe
      def initialize(config:, market_data:, logger:)
        @config      = config
        @market_data = market_data
        @logger      = logger
        @last_acted  = {}  # symbol → candle_ts of last acted-on entry candle
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

        return nil if h1_dir.nil? || m15_dir.nil? || m5_last_dir.nil?
        return nil if m15_adx_val.nil? || m15_adx_val < @config.adx_threshold

        # Check for fresh flip on 5M — previous direction must differ from current
        just_flipped = m5_prev_dir && m5_last_dir != m5_prev_dir

        return nil unless just_flipped
        return nil if @last_acted[symbol] == m5_last_ts

        side = if h1_dir == :bullish && m15_dir == :bullish && m5_last_dir == :bullish
                 :long
               elsif h1_dir == :bearish && m15_dir == :bearish && m5_last_dir == :bearish
                 :short
               end

        return nil unless side

        @last_acted[symbol] = m5_last_ts
        @logger.info("signal_generated", symbol: symbol, side: side, candle_ts: m5_last_ts)

        Signal.new(symbol: symbol, side: side, entry_price: current_price, candle_ts: m5_last_ts)
      end

      private

      def fetch_candles(symbol, resolution)
        end_ts   = Time.now.to_i
        start_ts = end_ts - (resolution.to_i * 60 * @config.candles_lookback)

        raw = @market_data.candles({
          "symbol"     => symbol,
          "resolution" => resolution,
          "start"      => start_ts,
          "end"        => end_ts
        })

        return [] unless raw.is_a?(Array)

        raw.map do |c|
          { open:      (c[:open]      || c["open"])&.to_f      || raise("missing open in candle"),
            high:      (c[:high]      || c["high"])&.to_f      || raise("missing high in candle"),
            low:       (c[:low]       || c["low"])&.to_f       || raise("missing low in candle"),
            close:     (c[:close]     || c["close"])&.to_f     || raise("missing close in candle"),
            timestamp: (c[:timestamp] || c["timestamp"] || c["time"])&.to_i || raise("missing timestamp in candle") }
        end
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
    end
  end
end
