# frozen_string_literal: true

module Trading
  module Analysis
    # Event-style SMC Telegram alerts (Pine alertcondition parity) for the configured entry timeframe.
    #
    # Bar vs tick: +SmcConfluence::Engine+ evaluates the latest candle from REST (including the forming
    # bar as Delta returns it). We do not run on every WebSocket tick — +acquire_eval_gate+ throttles
    # wall-clock evaluations; rising-edge detection avoids repeats while a condition stays true; Redis
    # cooldown dampens oscillation on the same forming bar.
    #
    # Heavy work (REST candles, confluence, optional Ollama) runs in +SmcAlertEvaluationJob+ so the
    # WebSocket thread only acquires the gate and enqueues.
    #
    # When any alert fires, optional Ollama synthesis (+DigestBuilder+ payload parity) runs **once** per burst;
    # the summary is attached to the **first** Telegram alert delivered in that pass (+ANALYSIS_SMC_ALERT_INCLUDE_AI+).
    class SmcAlertEvaluator
      HIGH_CONVICTION_SCORE_MIN = 5
      STATE_KEY = "delta:smc_alert:prev:%<symbol>s"
      GATE_KEY = "delta:smc_alert:gate:%<symbol>s"
      COOLDOWN_KEY = "delta:smc_alert:cooldown:%<symbol>s:%<alert_id>s"

      ALERTS = [
        { id: "long_signal", title: "▲ LONG Signal (SMC-CE)", body: "▲ LONG Signal" },
        { id: "short_signal", title: "▼ SHORT Signal (SMC-CE)", body: "▼ SHORT Signal" },
        { id: "high_conviction_long", title: "HIGH CONVICTION LONG (5+)", body: "LONG score≥5" },
        { id: "high_conviction_short", title: "HIGH CONVICTION SHORT (5+)", body: "SHORT score≥5" },
        { id: "liq_sweep_bull", title: "Sell-side Liquidity Taken", body: "Sell-side swept watch for CHOCH up" },
        { id: "liq_sweep_bear", title: "Buy-side Liquidity Taken", body: "Buy-side swept watch for CHOCH down" },
        { id: "choch_bull", title: "CHOCH Bullish", body: "CHOCH UP structure shifted bullish" },
        { id: "choch_bear", title: "CHOCH Bearish", body: "CHOCH DOWN structure shifted bearish" },
        { id: "pdh_sweep", title: "A PDH Swept", body: "Previous Day High swept reversal watch" },
        { id: "pdl_sweep", title: "A PDL Swept", body: "Previous Day Low swept — reversal watch" }
      ].freeze

      class << self
        def call(symbol:)
          sym = symbol.to_s.strip
          return if sym.empty?
          return unless feature_enabled?
          return unless telegram_analysis_enabled?
          return unless symbol_tracked?(sym)
          return unless acquire_eval_gate!(sym)

          SmcAlertEvaluationJob.perform_later(sym)
        end

        # Invoked only from +SmcAlertEvaluationJob+ (after tick path acquired the gate).
        def perform_evaluation!(symbol:)
          sym = symbol.to_s.strip
          return if sym.empty?
          return unless feature_enabled?
          return unless telegram_analysis_enabled?
          return unless symbol_tracked?(sym)

          evaluate_and_notify!(sym)
        end

        def flags_from_confluence(confluence)
          c = confluence.is_a?(Hash) ? confluence.stringify_keys : {}
          long_signal = truthy?(c["long_signal"])
          short_signal = truthy?(c["short_signal"])
          long_score = c["long_score"].to_i
          short_score = c["short_score"].to_i
          {
            "long_signal" => long_signal,
            "short_signal" => short_signal,
            "high_conviction_long" => long_signal && long_score >= HIGH_CONVICTION_SCORE_MIN,
            "high_conviction_short" => short_signal && short_score >= HIGH_CONVICTION_SCORE_MIN,
            "liq_sweep_bull" => truthy?(c["liq_sweep_bull"]),
            "liq_sweep_bear" => truthy?(c["liq_sweep_bear"]),
            "choch_bull" => truthy?(c["choch_bull"]),
            "choch_bear" => truthy?(c["choch_bear"]),
            "pdh_sweep" => truthy?(c["pdh_sweep"]),
            "pdl_sweep" => truthy?(c["pdl_sweep"])
          }
        end

        def truthy?(value)
          value == true || value.to_s == "true"
        end

        private

        def feature_enabled?
          ENV["ANALYSIS_SMC_ALERT_ENABLED"].to_s.strip.downcase != "false"
        end

        def telegram_analysis_enabled?
          cfg = Bot::Config.load
          cfg.telegram_enabled? && cfg.telegram_event_enabled?(:analysis)
        rescue Bot::Config::ValidationError
          false
        end

        def symbol_tracked?(sym)
          SymbolConfig.exists?(symbol: sym, enabled: true)
        end

        def acquire_eval_gate!(sym)
          Redis.current.set(
            format(GATE_KEY, symbol: sym),
            "1",
            nx: true,
            ex: min_interval_seconds
          )
        end

        def min_interval_seconds
          Integer(ENV.fetch("ANALYSIS_SMC_ALERT_MIN_INTERVAL_S", "15"))
        end

        def cooldown_seconds
          Integer(ENV.fetch("ANALYSIS_SMC_ALERT_COOLDOWN_S", "300"))
        end

        def include_ai_insight?
          ENV["ANALYSIS_SMC_ALERT_INCLUDE_AI"].to_s.strip.downcase != "false"
        end

        def fired_alerts(current, prev)
          ALERTS.select do |meta|
            id = meta[:id]
            truthy?(current[id]) && !truthy?(prev[id])
          end
        end

        def fetch_ai_insight_for_burst(sym:, config:, market_data:, trend_tf:, confirm_tf:, entry_tf:,
                                      candles_trend:, candles_confirm:, candles_entry:, smc_confluence_mtf:)
          bundle = DigestBuilder.ai_synthesis_from_loaded_candles(
            symbol: sym,
            market_data: market_data,
            config: config,
            ollama_connection_settings: Ai::OllamaClient.read_connection_settings,
            trend_tf: trend_tf,
            confirm_tf: confirm_tf,
            entry_tf: entry_tf,
            candles_trend: candles_trend,
            candles_confirm: candles_confirm,
            candles_entry: candles_entry,
            smc_confluence_mtf: smc_confluence_mtf
          )
          bundle[:ai_insight].to_s.strip.presence
        rescue StandardError => e
          HotPathErrorPolicy.log_swallowed_error(
            component: "SmcAlertEvaluator",
            operation: "fetch_ai_insight_for_burst",
            error:     e,
            log_level: :warn,
            symbol:    sym
          )
          nil
        end

        def evaluate_and_notify!(sym)
          config = Bot::Config.load
          market_data = RunnerClient.build.market_data
          trend_tf = config.timeframe_trend.to_s
          confirm_tf = config.timeframe_confirm.to_s
          entry_tf = config.timeframe_entry.to_s
          required = config.min_candles_required

          candles_trend = HistoricalCandles.fetch(market_data: market_data, config: config, symbol: sym, resolution: trend_tf)
          candles_confirm = HistoricalCandles.fetch(market_data: market_data, config: config, symbol: sym, resolution: confirm_tf)
          candles_entry = HistoricalCandles.fetch(market_data: market_data, config: config, symbol: sym, resolution: entry_tf)
          return if candles_trend.size < required || candles_confirm.size < required || candles_entry.size < required

          mtf = SmcConfluenceMtf.from_timeframe_candles(
            symbol: sym,
            timeframe_candles: {
              trend_tf => candles_trend,
              confirm_tf => candles_confirm,
              entry_tf => candles_entry
            }
          )

          confluence = mtf.dig("timeframes", entry_tf, "confluence")
          return unless confluence.is_a?(Hash)

          current = flags_from_confluence(confluence)
          state_key = format(STATE_KEY, symbol: sym)
          prev_raw = Redis.current.get(state_key)
          prev = parse_prev_flags(prev_raw, sym: sym)

          if prev.empty?
            Redis.current.set(state_key, JSON.generate(current))
            return
          end

          ltp = read_ltp(sym)
          entry_resolution = entry_tf
          fired = fired_alerts(current, prev)

          ai_insight = nil
          if fired.any? && include_ai_insight?
            ai_insight = fetch_ai_insight_for_burst(
              sym: sym,
              config: config,
              market_data: market_data,
              trend_tf: trend_tf,
              confirm_tf: confirm_tf,
              entry_tf: entry_tf,
              candles_trend: candles_trend,
              candles_confirm: candles_confirm,
              candles_entry: candles_entry,
              smc_confluence_mtf: mtf
            )
          end

          fired.each_with_index do |meta, index|
            id = meta[:id]
            next if cooldown_active?(sym, id)

            insight_for_message = (index.zero? ? ai_insight : nil)
            deliver_alert!(sym, meta, ltp: ltp, resolution: entry_resolution, ai_insight: insight_for_message)
            arm_cooldown!(sym, id)
          end

          Redis.current.set(state_key, JSON.generate(current))
        end

        def read_ltp(sym)
          raw = Rails.cache.read("ltp:#{sym}")
          d = raw&.to_d
          d&.positive? ? d : nil
        end

        def cooldown_active?(sym, alert_id)
          Redis.current.exists?(format(COOLDOWN_KEY, symbol: sym, alert_id: alert_id))
        end

        def arm_cooldown!(sym, alert_id)
          Redis.current.set(
            format(COOLDOWN_KEY, symbol: sym, alert_id: alert_id),
            "1",
            ex: cooldown_seconds
          )
        end

        def deliver_alert!(sym, meta, ltp:, resolution:, ai_insight:)
          Trading::TelegramNotifications.deliver do |notifier|
            notifier.notify_smc_confluence_event(
              symbol: sym,
              title: meta[:title],
              message_line: meta[:body],
              ltp: ltp,
              resolution: resolution,
              ai_insight: ai_insight
            )
          end
        end

        def parse_prev_flags(raw, sym:)
          return {} if raw.blank?

          JSON.parse(raw)
        rescue JSON::ParserError => e
          HotPathErrorPolicy.log_swallowed_error(
            component: "SmcAlertEvaluator",
            operation: "parse_prev_flags",
            error:     e,
            log_level: :warn,
            symbol:    sym
          )
          {}
        end
      end
    end
  end
end
