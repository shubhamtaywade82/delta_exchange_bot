# frozen_string_literal: true

require "time"
require_relative "supertrend"
require_relative "adx"
require_relative "signal"
require_relative "indicators/rsi"
require_relative "indicators/vwap"
require_relative "indicators/bos"
require_relative "indicators/order_block"
require_relative "filters/momentum_filter"
require_relative "filters/volume_filter"
require_relative "filters/derivatives_filter"

module Bot
  module Strategy
    class MultiTimeframe
      def initialize(config:, market_data:, logger:, cvd_store: nil, derivatives_store: nil)
        @config            = config
        @market_data       = market_data
        @logger            = logger
        @cvd_store         = cvd_store
        @derivatives_store = derivatives_store
        @last_acted        = {}
        @signal_state      = {}
      end

      def state_for(symbol)
        @signal_state[symbol]
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
        h1_dir       = h1_st.last[:direction]
        m15_dir      = m15_st.last[:direction]
        m15_adx_val  = m15_adx.last[:adx]

        if h1_dir.nil? || m15_dir.nil?
          @logger.debug("strategy_skip", symbol: symbol, reason: "nil_direction",
                        h1: h1_dir, m15: m15_dir)
          return nil
        end

        unless h1_dir == m15_dir
          @logger.debug("strategy_skip", symbol: symbol, reason: "no_regime_confluence",
                        h1: h1_dir, m15: m15_dir)
          return nil
        end

        if m15_adx_val.nil? || m15_adx_val < @config.adx_threshold
          @logger.debug("strategy_skip", symbol: symbol, reason: "adx_below_threshold",
                        adx: m15_adx_val&.round(2), threshold: @config.adx_threshold)
          return nil
        end

        # --- Entry: BOS + Order Block on 5M ---
        m5_rsi  = Indicators::RSI.compute(m5_candles,  period: @config.rsi_period)
        m5_vwap = Indicators::VWAP.compute(m5_candles, session_reset_hour_utc: @config.vwap_session_reset_hour_utc)
        m5_bos  = Indicators::BOS.compute(m5_candles,  swing_lookback: @config.bos_swing_lookback)
        m5_obs  = Indicators::OrderBlock.compute(m5_candles,
                    min_impulse_pct: @config.ob_min_impulse_pct,
                    max_ob_age:      @config.ob_max_age)

        bos_last  = m5_bos.last
        rsi_last  = m5_rsi.last
        vwap_last = m5_vwap.last
        m5_last_ts = m5_candles.last[:timestamp].to_i

        @signal_state[symbol] = {
          h1_dir:          h1_dir&.to_s,
          m15_dir:         m15_dir&.to_s,
          adx:             m15_adx_val&.round(2),
          bos_direction:   bos_last[:direction]&.to_s,
          bos_level:       bos_last[:level],
          rsi:             rsi_last[:value],
          vwap:            vwap_last[:vwap],
          vwap_deviation_pct: vwap_last[:deviation_pct],
          order_blocks:    m5_obs.map { |ob| { side: ob[:side].to_s, high: ob[:high], low: ob[:low], fresh: ob[:fresh] } },
          signal:          nil,
          updated_at:      Time.now.utc.iso8601
        }

        # BOS must be confirmed in the same direction as regime
        unless bos_last[:confirmed] && bos_last[:direction] == h1_dir
          @logger.debug("strategy_skip", symbol: symbol, reason: "no_bos",
                        bos_confirmed: bos_last[:confirmed], bos_dir: bos_last[:direction], h1: h1_dir)
          return nil
        end

        side = h1_dir == :bullish ? :long : :short
        signal_side_for_ob = h1_dir  # :bullish or :bearish maps to :bull/:bear OB

        # OB confirmation required in live modes; relaxed in dry_run (same as flip was)
        ob_ok = @config.dry_run? ||
                m5_obs.any? { |ob| ob[:side] == (signal_side_for_ob == :bullish ? :bull : :bear) && ob[:fresh] }

        unless ob_ok
          @logger.debug("strategy_skip", symbol: symbol, reason: "no_fresh_ob", side: side)
          return nil
        end

        if @last_acted[symbol] == m5_last_ts
          @logger.debug("strategy_skip", symbol: symbol, reason: "stale_candle", candle_ts: m5_last_ts)
          return nil
        end

        # --- Filter chain ---
        cvd_data         = @cvd_store&.get(symbol)
        derivatives_data = @derivatives_store&.get(symbol)

        filter_results = {
          momentum:    Filters::MomentumFilter.check(side, rsi_last),
          volume:      Filters::VolumeFilter.check(side, cvd_data, current_price, vwap_last),
          derivatives: Filters::DerivativesFilter.check(derivatives_data)
        }

        @signal_state[symbol] = @signal_state[symbol].merge(
          cvd_trend:       cvd_data&.dig(:delta_trend)&.to_s,
          cvd_delta:       cvd_data&.dig(:cumulative_delta),
          oi_usd:          derivatives_data&.dig(:oi_usd),
          oi_trend:        derivatives_data&.dig(:oi_trend)&.to_s,
          funding_rate:    derivatives_data&.dig(:funding_rate),
          funding_extreme: derivatives_data&.dig(:funding_extreme),
          filters:         filter_results.transform_values { |f| { passed: f[:passed], reason: f[:reason] } }
        )

        blocked = filter_results.find { |_k, f| !f[:passed] }
        if blocked
          @logger.debug("strategy_skip", symbol: symbol, reason: "filter_blocked",
                        filter: blocked[0], detail: blocked[1][:reason])
          return nil
        end

        @last_acted[symbol] = m5_last_ts
        @signal_state[symbol] = @signal_state[symbol].merge(signal: side.to_s)
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
            volume:    (c[:volume]    || c["volume"])&.to_f    || 0.0,
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
    end
  end
end
