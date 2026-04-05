# frozen_string_literal: true

require_relative "adx"
require_relative "indicator_factory"
require_relative "indicators/rsi"
require_relative "indicators/vwap"
require_relative "indicators/cvd_calculator"
require_relative "filters/momentum_filter"
require_relative "filters/volume_filter"
require_relative "filters/derivatives_filter"
require "redis"
require "securerandom"
require "timeout"
require "active_support/core_ext/time"

module Bot
  module Strategy
    class MultiTimeframe
      # REST calls after candles can stall indefinitely (no default Net::HTTP read timeout).
      # WebSocket ticks still update Rails.cache LTP while the main loop is blocked — UI looks "live"
      # but Redis strategy state stops refreshing. Keep these bounded.
      REST_FETCH_TIMEOUT_S =
        Integer(ENV.fetch("STRATEGY_REST_FETCH_TIMEOUT_S", "12"))
      CANDLE_FETCH_TIMEOUT_S =
        Integer(ENV.fetch("STRATEGY_CANDLE_FETCH_TIMEOUT_S", "25"))
      # Space out trend / confirm / entry candle requests (same symbol) to avoid public /history burst limits.
      CANDLE_RESOLUTION_STAGGER_S =
        Float(ENV.fetch("STRATEGY_CANDLE_RESOLUTION_STAGGER_S", "0.4"))
      CANDLE_FETCH_MAX_ATTEMPTS =
        Integer(ENV.fetch("STRATEGY_CANDLE_FETCH_MAX_ATTEMPTS", "3"))
      CANDLE_RETRY_BASE_SLEEP_S =
        Float(ENV.fetch("STRATEGY_CANDLE_RETRY_BASE_SLEEP_S", "1.25"))
      # History APIs usually omit the in-progress bar at `end`; a window of exactly N periods
      # then returns N−1 closed bars. Fetch one extra period, then keep the newest `candles_lookback`.
      LOOKBACK_SLACK_BARS = 1
      def initialize(config:, market_data:, logger:)
        @config      = config
        @market_data = market_data
        @logger      = logger
        @last_acted  = {}  # symbol → candle_ts of last acted-on entry candle
        @redis       = Redis.new
      end

      # Returns a Signal or nil
      # Supertrend (including ML adaptive when configured) runs on trend, confirm, and entry resolutions.
      def evaluate(symbol, current_price:)
        Bot::StructuredLog.log(@logger, :info, "evaluating_symbol", symbol: symbol, price: current_price)
        trend_candles  = fetch_candles(symbol, @config.timeframe_trend)
        sleep_candle_resolution_stagger
        confirm_candles = fetch_candles(symbol, @config.timeframe_confirm)
        sleep_candle_resolution_stagger
        entry_candles   = fetch_candles(symbol, @config.timeframe_entry)

        req = @config.effective_min_candles_for_supertrend
        tf_trend = timeframe_tag(@config.timeframe_trend)
        tf_confirm = timeframe_tag(@config.timeframe_confirm)
        tf_entry = timeframe_tag(@config.timeframe_entry)
        candle_counts = {
          tf_trend => trend_candles.size,
          tf_confirm => confirm_candles.size,
          tf_entry => entry_candles.size
        }

        unless sufficient?(trend_candles, symbol, tf_trend)
          persist_evaluation_blocked(
            symbol,
            current_price: current_price,
            reason: :insufficient_candles,
            insufficient_timeframe: tf_trend,
            candle_counts_by_timeframe: candle_counts,
            min_candles_required: req
          )
          return nil
        end
        unless sufficient?(confirm_candles, symbol, tf_confirm)
          persist_evaluation_blocked(
            symbol,
            current_price: current_price,
            reason: :insufficient_candles,
            insufficient_timeframe: tf_confirm,
            candle_counts_by_timeframe: candle_counts,
            min_candles_required: req
          )
          return nil
        end
        unless sufficient?(entry_candles, symbol, tf_entry)
          persist_evaluation_blocked(
            symbol,
            current_price: current_price,
            reason: :insufficient_candles,
            insufficient_timeframe: tf_entry,
            candle_counts_by_timeframe: candle_counts,
            min_candles_required: req
          )
          return nil
        end

        trend_st   = IndicatorFactory.compute_supertrend(trend_candles, config: @config)
        confirm_st = IndicatorFactory.compute_supertrend(confirm_candles, config: @config)
        confirm_adx = ADX.compute(confirm_candles, period: @config.adx_period)
        entry_st = IndicatorFactory.compute_supertrend(entry_candles, config: @config)

        # New Indicators
        confirm_rsi = Indicators::RSI.compute(confirm_candles, period: 14)
        entry_vwap = Indicators::VWAP.compute(entry_candles)

        current_vwap = entry_vwap.last
        rsi_val      = confirm_rsi.last
        adx_val      = confirm_adx.last[:adx]
        trend_dir    = trend_st.last[:direction]
        confirm_dir  = confirm_st.last[:direction]
        entry_prev_dir = entry_st[-2]&.dig(:direction)
        entry_last_dir = entry_st.last[:direction]
        entry_last_ts = entry_candles.last[:timestamp].to_i

        # Real-time Metrics from Delta Exchange API (bounded — see class comment)
        ticker = fetch_ticker(symbol)
        raw_trades = fetch_recent_trades(symbol)
        trades = if raw_trades.is_a?(Hash) && raw_trades.key?("result")
                   raw_trades["result"]
                 elsif raw_trades.is_a?(Hash) && raw_trades.key?(:result)
                   raw_trades[:result]
                 else
                   raw_trades
                 end
        cvd_data = Indicators::CvdCalculator.compute(trades)

        deriv_data = if ticker
                       {
                         oi_trend: :neutral,
                         funding_rate: ticker.funding_rate.to_f,
                         funding_extreme: ticker.funding_rate.to_f.abs > 0.0005,
                         oi_usd: ticker.oi_value_usd.to_f
                       }
                     else
                       { oi_trend: :neutral, funding_rate: 0.0, funding_extreme: false, oi_usd: 0.0 }
                     end

        # Run Filters with Real Data
        potential_side = trend_dir == :bullish ? :long : :short
        mom_res = Filters::MomentumFilter.check(potential_side, rsi_val, logger: @logger)
        vol_res = Filters::VolumeFilter.check(potential_side, cvd_data, current_price, current_vwap, logger: @logger)
        der_res = Filters::DerivativesFilter.check(deriv_data)

        # Extraction for signal check
        mom_f = mom_res.is_a?(Hash) ? mom_res[:passed] : mom_res
        vol_f = vol_res.is_a?(Hash) ? vol_res[:passed] : vol_res
        der_f = der_res.is_a?(Hash) ? der_res[:passed] : der_res

        # MANDATORY: Update UI even if we skip trade logic
        persist_symbol_state(symbol, {
          trend_dir: trend_dir,
          confirm_dir: confirm_dir,
          entry_dir: entry_last_dir,
          entry_timeframe: @config.timeframe_entry,
          adx: adx_val,
          rsi: rsi_val ? rsi_val[:value] : nil,
          vwap: current_vwap[:vwap],
          vwap_deviation_pct: current_vwap[:deviation_pct],
          cvd_trend: cvd_data[:delta_trend],
          cvd_delta: cvd_data[:delta],
          cvd_delta_pct: cvd_data[:delta_pct],
          oi_trend: deriv_data[:oi_trend],
          oi_usd: deriv_data[:oi_usd],
          funding_rate: deriv_data[:funding_rate],
          filters: {
            momentum: mom_res,
            volume: vol_res,
            derivatives: der_res
          },
          ltp_evaluated: current_price,
          evaluation_blocked: false,
          evaluation_block_reason: nil,
          insufficient_timeframe: nil,
          candle_counts_by_timeframe: nil,
          min_candles_required: nil,
          updated_at: Time.current.iso8601
        })

        # --- TRADE LOGIC ---
        if trend_dir.nil? || confirm_dir.nil? || entry_last_dir.nil?
          Bot::StructuredLog.log(@logger, :info, "strategy_skip", symbol: symbol, reason: "nil_direction")
          return nil
        end

        if adx_val.nil? || adx_val < @config.adx_threshold
          Bot::StructuredLog.log(@logger, :info, "strategy_skip", symbol: symbol, reason: "adx_below_threshold",
            adx: adx_val)
          return nil
        end

        # Flip logic: In dry_run we allow continuation, in live we strictly want the fresh flip
        just_flipped = entry_prev_dir && entry_last_dir != entry_prev_dir
        unless just_flipped || @config.dry_run?
          Bot::StructuredLog.log(@logger, :info, "strategy_skip", symbol: symbol, reason: "no_entry_timeframe_flip")
          return nil
        end

        if @last_acted[symbol] == entry_last_ts
          return nil
        end

        side = if trend_dir == :bullish && confirm_dir == :bullish && entry_last_dir == :bullish
                 :long
               elsif trend_dir == :bearish && confirm_dir == :bearish && entry_last_dir == :bearish
                 :short
               end

        unless side
          Bot::StructuredLog.log(
            @logger,
            :info,
            "strategy_skip",
            symbol: symbol,
            reason: "no_confluence",
            trend: trend_dir,
            confirm: confirm_dir,
            entry: entry_last_dir
          )
          return nil
        end

        relaxed_vol_f = vol_f || relaxed_volume_allowed?(cvd_data)
        # In dry-run demo mode we can relax neutral CVD/funding filters
        # to verify full entry -> position -> trailing-exit pipeline.
        unless mom_f && relaxed_vol_f
          Bot::StructuredLog.log(
            @logger,
            :info,
            "strategy_skip",
            symbol: symbol,
            reason: "filters_failed",
            mom: mom_f,
            vol: vol_f,
            der: der_f,
            relaxed_vol: relaxed_vol_f
          )
          return nil
        end

        @last_acted[symbol] = entry_last_ts
        signal_id = SecureRandom.uuid
        Bot::StructuredLog.log(@logger, :info, "signal_generated", signal_id: signal_id, symbol: symbol, side: side,
          price: current_price)

        Signal.new(symbol: symbol, side: side, entry_price: current_price, candle_ts: entry_last_ts, signal_id: signal_id)
      end

      private

      def fetch_candles(symbol, resolution)
        required = @config.effective_min_candles_for_supertrend
        attempts = [CANDLE_FETCH_MAX_ATTEMPTS, 1].max
        last = []

        attempts.times do |attempt|
          last = fetch_candles_once(symbol, resolution)
          return last if last.size >= required

          next if attempt >= attempts - 1

          delay = CANDLE_RETRY_BASE_SLEEP_S * (attempt + 1)
          Bot::StructuredLog.log(
            @logger,
            :warn,
            "candle_fetch_retry",
            symbol: symbol,
            resolution: resolution,
            attempt: attempt + 1,
            count: last.size,
            required: required,
            sleep_s: delay
          )
          sleep(delay)
        end

        last
      end

      def fetch_candles_once(symbol, resolution)
        end_ts   = Time.now.to_i
        span_bars = @config.candles_lookback + LOOKBACK_SLACK_BARS
        start_ts = end_ts - (resolution_to_seconds(resolution) * span_bars)

        raw = Timeout.timeout(CANDLE_FETCH_TIMEOUT_S) do
          @market_data.candles({
            "symbol"     => symbol,
            "resolution" => resolution,
            "start"      => start_ts,
            "end"        => end_ts
          })
        end

        # Handle nested result array if present
        candles_payload = if raw.is_a?(Hash) && raw.key?("result")
                           raw["result"]
                         elsif raw.is_a?(Hash) && raw.key?(:result)
                           raw[:result]
                         else
                           raw
                         end

        return [] unless candles_payload.is_a?(Array)

        rows = candles_payload.map do |c|
          { open:      (c[:open]      || c["open"])&.to_f      || raise("missing open in candle"),
            high:      (c[:high]      || c["high"])&.to_f      || raise("missing high in candle"),
            low:       (c[:low]       || c["low"])&.to_f       || raise("missing low in candle"),
            close:     (c[:close]     || c["close"])&.to_f     || raise("missing close in candle"),
            volume:    (c[:volume]    || c["volume"])&.to_f    || 0.0,
            timestamp: (c[:timestamp] || c["timestamp"] || c[:time] || c["time"])&.to_i || raise("missing timestamp in candle") }
        end.sort_by { |c| c[:timestamp] }

        cap_candles_to_lookback(rows)
      rescue Timeout::Error
        Bot::StructuredLog.log(
          @logger,
          :warn,
          "candle_fetch_timeout",
          symbol: symbol, resolution: resolution, timeout_s: CANDLE_FETCH_TIMEOUT_S
        )
        []
      rescue StandardError => e
        Bot::StructuredLog.log(@logger, :error, "candle_fetch_failed", symbol: symbol, resolution: resolution,
          message: e.message)
        []
      end

      def cap_candles_to_lookback(rows)
        limit = @config.candles_lookback
        return rows if rows.size <= limit

        rows.last(limit)
      end

      def sleep_candle_resolution_stagger
        return if CANDLE_RESOLUTION_STAGGER_S <= 0

        sleep(CANDLE_RESOLUTION_STAGGER_S)
      end

      def sufficient?(candles, symbol, label)
        required = @config.effective_min_candles_for_supertrend
        if candles.size < required
          Bot::StructuredLog.log(
            @logger,
            :warn,
            "insufficient_candles",
            symbol: symbol, timeframe: label, count: candles.size, required: required
          )
          return false
        end
        true
      end

      def resolution_to_seconds(resolution)
        match = resolution.to_s.match(/(\d+)([smhdw])/)
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

      def timeframe_tag(resolution)
        resolution.to_s.strip.downcase.sub(/([smhdw])$/) { |u| u.upcase }
      end

      def persist_symbol_state(symbol, data)
        # Using the same key as the StrategyStatusController
        @redis.hset("delta:strategy:state", symbol, data.to_json)
      rescue StandardError => e
        Bot::StructuredLog.log(@logger, :error, "strategy_persistence_failed", symbol: symbol, message: e.message)
      end

      def persist_evaluation_blocked(symbol, current_price:, reason:, **extra)
        persist_symbol_state(
          symbol,
          cleared_indicator_payload.merge(
            updated_at: Time.current.iso8601,
            ltp_evaluated: current_price,
            evaluation_blocked: true,
            evaluation_block_reason: reason.to_s,
            **extra
          )
        )
      end

      def cleared_indicator_payload
        {
          trend_dir: nil,
          confirm_dir: nil,
          entry_dir: nil,
          entry_timeframe: @config.timeframe_entry,
          adx: nil,
          rsi: nil,
          vwap: nil,
          vwap_deviation_pct: nil,
          cvd_trend: nil,
          cvd_delta: nil,
          cvd_delta_pct: nil,
          oi_trend: nil,
          oi_usd: nil,
          funding_rate: nil,
          filters: { momentum: nil, volume: nil, derivatives: nil }
        }
      end

      def relaxed_volume_allowed?(cvd_data)
        return false unless relaxed_filters_in_dry_run?

        cvd_data && cvd_data[:delta_trend] == :neutral
      end

      def relaxed_filters_in_dry_run?
        @config.dry_run? && @config.respond_to?(:relax_filters_in_dry_run?) && @config.relax_filters_in_dry_run?
      end

      def fetch_ticker(symbol)
        Timeout.timeout(REST_FETCH_TIMEOUT_S) { DeltaExchange::Models::Ticker.find(symbol) }
      rescue Timeout::Error
        Bot::StructuredLog.log(@logger, :warn, "ticker_fetch_timeout", symbol: symbol, timeout_s: REST_FETCH_TIMEOUT_S)
        nil
      rescue StandardError
        nil
      end

      def fetch_recent_trades(symbol)
        Timeout.timeout(REST_FETCH_TIMEOUT_S) { @market_data.trades(symbol, { limit: 100 }) }
      rescue Timeout::Error
        Bot::StructuredLog.log(@logger, :warn, "trades_fetch_timeout", symbol: symbol, timeout_s: REST_FETCH_TIMEOUT_S)
        nil
      rescue StandardError
        nil
      end
    end
  end
end
