# frozen_string_literal: true

module Trading
  module Analysis
    # Builds a JSON-serializable multi-timeframe SMC digest (5m / 15m / 1h) + heuristic trade plan + Ollama JSON synthesis.
    class DigestBuilder
      STRUCTURE_TREND = "1h"
      STRUCTURE_CONFIRM = "15m"
      STRUCTURE_ENTRY = "5m"

      def self.call(symbol:, market_data:, config:)
        new(symbol: symbol, market_data: market_data, config: config).build
      end

      def initialize(symbol:, market_data:, config:)
        @symbol = symbol
        @market_data = market_data
        @config = config
      end

      def build
        candles_1h = fetch(STRUCTURE_TREND)
        candles_15m = fetch(STRUCTURE_CONFIRM)
        candles_5m = fetch(STRUCTURE_ENTRY)
        required = @config.min_candles_required

        return insufficient(@symbol, :trend_1h, candles_1h.size, required) if candles_1h.size < required
        return insufficient(@symbol, :confirm_15m, candles_15m.size, required) if candles_15m.size < required
        return insufficient(@symbol, :entry_5m, candles_5m.size, required) if candles_5m.size < required

        trend_st = supertrend_last(candles_1h)
        confirm_st = supertrend_last(candles_15m)
        entry_st = supertrend_last(candles_5m)
        m15_adx = Bot::Strategy::ADX.compute(candles_15m, period: @config.adx_period).last

        structure = structure_summary(trend_st, confirm_st, entry_st, m15_adx)

        smc_by_timeframe = {
          "5m" => round_smc_snapshot(Trading::Analysis::SmcSnapshot.build(candles: candles_5m, resolution: "5m")),
          "15m" => round_smc_snapshot(Trading::Analysis::SmcSnapshot.build(candles: candles_15m, resolution: "15m")),
          "1h" => round_smc_snapshot(Trading::Analysis::SmcSnapshot.build(candles: candles_1h, resolution: "1h"))
        }

        last_bar = candles_5m.last
        last_close = last_bar[:close].to_f
        ltp = Rails.cache.read("ltp:#{@symbol}")&.to_f

        trade_plan = round_trade_plan(
          Trading::Analysis::TradePlanBuilder.call(
            smc_by_timeframe: smc_by_timeframe,
            last_price: ltp.positive? ? ltp : last_close,
            structure_bias: structure[:bias]
          )
        )

        legacy_smc = legacy_smc_from(smc_by_timeframe["5m"])

        ai_payload = {
          smc_model_version: "2",
          symbol: @symbol,
          generated_at_utc: Time.current.utc.iso8601,
          market_structure: structure,
          mtf_alignment: mtf_alignment(smc_by_timeframe, structure),
          risk_and_execution_framework: risk_execution_framework,
          smc_by_timeframe: smc_by_timeframe,
          trade_plan: trade_plan
        }
        ai_smc = Trading::Analysis::AiSmcSynthesizer.call(symbol: @symbol, payload: ai_payload)
        ai_smc = stringify_ai_smc(ai_smc) if ai_smc.is_a?(Hash)

        {
          symbol: @symbol,
          error: nil,
          updated_at: Time.current.iso8601,
          ai_insight: ai_smc&.dig("summary"),
          ai_smc: ai_smc,
          price_action: {
            last_close: round_price(last_close),
            ltp: ltp.positive? ? round_price(ltp) : nil,
            entry_timeframe: STRUCTURE_ENTRY,
            last_bar_at: Time.zone.at(last_bar[:timestamp]).iso8601
          },
          market_structure: structure,
          timeframes: {
            trend: timeframe_digest(STRUCTURE_TREND, candles_1h, trend_st),
            confirm: timeframe_digest(STRUCTURE_CONFIRM, candles_15m, confirm_st),
            entry: timeframe_digest(STRUCTURE_ENTRY, candles_5m, entry_st)
          },
          smc_by_timeframe: smc_by_timeframe,
          trade_plan: trade_plan,
          smc: legacy_smc,
          smc_model_version: "2",
          mtf_alignment: mtf_alignment(smc_by_timeframe, structure),
          risk_and_execution_framework: risk_execution_framework
        }
      end

      private

      def mtf_alignment(smc_by_timeframe, structure)
        h1 = smc_by_timeframe["1h"]
        m15 = smc_by_timeframe["15m"]
        m5 = smc_by_timeframe["5m"]
        {
          htf_1h_trend_type: h1&.dig("structure_sequence", "trend_type"),
          mtf_15m_trend_type: m15&.dig("structure_sequence", "trend_type"),
          ltf_5m_trend_type: m5&.dig("structure_sequence", "trend_type"),
          roles: {
            "1h" => "bias_liquidity_external_structure",
            "15m" => "setup_fvg_internal_flow",
            "5m" => "entry_mitigation_sweeps"
          },
          supertrend_packaging_bias: structure[:bias],
          workflow_hint: "Structure + liquidity context before entry; use entry_model_flags on 5m for trigger quality."
        }
      end

      def risk_execution_framework
        {
          min_suggested_rr: Float(ENV.fetch("ANALYSIS_MIN_SUGGESTED_RR", "2.0")),
          position_sizing_note: "Not computed in digest — apply fixed fractional risk in execution layer.",
          stop_placement_preference: "Structural: beyond invalidated OB / opposite side of swept liquidity when visible.",
          profit_taking_style: "Scale at TP1/TP2; runner optional toward next liquidity pool.",
          smc_invariants_in_data: [
            "BOS uses close beyond swing window (not wick-only).",
            "CHOCH uses shorter pivot memory than external BOS.",
            "EQH/EQL = clustered pivot levels within tolerance %.",
            "Session ranges = UTC buckets (asian/london/new_york) over loaded candles."
          ]
        }
      end

      def fetch(resolution)
        HistoricalCandles.fetch(market_data: @market_data, config: @config, symbol: @symbol, resolution: resolution)
      end

      def supertrend_last(candles)
        Bot::Strategy::IndicatorFactory.compute_supertrend(candles, config: @config).last
      end

      def legacy_smc_from(m5)
        return { bos: {}, order_blocks: [] } if m5.nil? || !m5.is_a?(Hash)

        m5 = m5.stringify_keys
        return { bos: {}, order_blocks: [] } if m5["error"].present?

        bos = m5["bos"]
        obs = m5["order_blocks"] || []
        {
          bos: {
            direction: bos&.dig("direction"),
            level: round_price(bos&.dig("level")),
            confirmed: bos&.dig("confirmed")
          },
          order_blocks: obs.map { |ob| serialize_legacy_ob(ob.stringify_keys) }
        }
      end

      def serialize_legacy_ob(ob)
        {
          side: ob["side"],
          high: round_price(ob["high"]),
          low: round_price(ob["low"]),
          age_bars: ob["age_bars"],
          fresh: ob["fresh"],
          strength_pct: ob["strength_pct"]
        }
      end

      def round_smc_snapshot(snap)
        return snap unless snap.is_a?(Hash)

        out = snap.stringify_keys
        out["bos"] = round_bos(out["bos"]) if out["bos"].is_a?(Hash)
        out["choch"] = round_choch(out["choch"]) if out["choch"].is_a?(Hash)
        out["fair_value_gaps"] = (out["fair_value_gaps"] || []).map { |f| round_fvg(f) }
        out["order_blocks"] = (out["order_blocks"] || []).map { |ob| round_ob(ob) }
        out["liquidity"] = round_liquidity(out["liquidity"]) if out["liquidity"].is_a?(Hash)
        round_structure_sequence!(out)
        round_internal_external!(out)
        round_liquidity_pools!(out)
        round_premium_discount!(out)
        round_session_ranges!(out)
        round_volatility!(out)
        out
      end

      def round_structure_sequence!(out)
        seq = out["structure_sequence"]
        return unless seq.is_a?(Hash)

        (seq["recent_swings"] || []).each do |sw|
          next unless sw.is_a?(Hash)

          sw["price"] = round_price(sw["price"])
        end
      end

      def round_internal_external!(out)
        ie = out["internal_external_structure"]
        return unless ie.is_a?(Hash)

        %w[external internal].each do |k|
          next unless ie[k].is_a?(Hash)

          ie[k]["level"] = round_price(ie[k]["level"])
        end
      end

      def round_liquidity_pools!(out)
        pools = out["liquidity_pools"]
        return unless pools.is_a?(Hash)

        (pools["equal_high_clusters"] || []).each { |c| round_liquidity_cluster!(c) }
        (pools["equal_low_clusters"] || []).each { |c| round_liquidity_cluster!(c) }
        pools["swing_high_liquidity"] = (pools["swing_high_liquidity"] || []).map { |p| round_price(p) }
        pools["swing_low_liquidity"] = (pools["swing_low_liquidity"] || []).map { |p| round_price(p) }
      end

      def round_liquidity_cluster!(c)
        return unless c.is_a?(Hash)

        c["center"] = round_price(c["center"])
        c["members"] = (c["members"] || []).map { |p| round_price(p) }
      end

      def round_premium_discount!(out)
        pd = out["premium_discount"]
        return unless pd.is_a?(Hash)

        pd["range_high"] = round_price(pd["range_high"])
        pd["range_low"] = round_price(pd["range_low"])
      end

      def round_session_ranges!(out)
        sess = out["session_liquidity_ranges"]
        return unless sess.is_a?(Hash)

        sess.each_value do |v|
          next unless v.is_a?(Hash)

          v["high"] = round_price(v["high"])
          v["low"] = round_price(v["low"])
        end
      end

      def round_volatility!(out)
        vol = out["volatility"]
        return unless vol.is_a?(Hash)

        vol["atr"] = round_price(vol["atr"])
        vol["last_range"] = round_price(vol["last_range"])
      end

      def round_bos(bos)
        bos = bos.stringify_keys
        bos["level"] = round_price(bos["level"])
        bos
      end

      def round_choch(ch)
        ch = ch.stringify_keys
        ch["level"] = round_price(ch["level"])
        ch
      end

      def round_fvg(f)
        f = f.stringify_keys
        f["low"] = round_price(f["low"])
        f["high"] = round_price(f["high"])
        f
      end

      def round_ob(ob)
        ob = ob.stringify_keys
        ob["low"] = round_price(ob["low"])
        ob["high"] = round_price(ob["high"])
        ob
      end

      def round_liquidity(l)
        l = l.stringify_keys
        l["level"] = round_price(l["level"])
        l
      end

      def round_trade_plan(plan)
        return plan unless plan.is_a?(Hash)

        p = plan.stringify_keys
        %w[entry stop_loss take_profit_1 take_profit_2 take_profit_3].each do |k|
          p[k] = round_price(p[k])
        end
        p
      end

      def stringify_ai_smc(obj)
        case obj
        when Hash
          obj.stringify_keys.transform_values { |v| stringify_ai_smc(v) }
        when Array
          obj.map { |x| stringify_ai_smc(x) }
        else
          obj
        end
      end

      def insufficient(symbol, tf, got, need)
        {
          symbol: symbol,
          error: "insufficient_candles_#{tf}",
          candle_count: got,
          required: need,
          updated_at: Time.current.iso8601
        }
      end

      def round_price(value)
        return nil if value.nil?

        value.to_d.round(4).to_f
      end

      def timeframe_digest(resolution, candles, st_last)
        last = candles.last
        {
          resolution: resolution,
          bars: candles.size,
          supertrend_direction: st_last[:direction]&.to_s,
          close: round_price(last[:close]),
          last_at: Time.zone.at(last[:timestamp]).iso8601
        }
      end

      def structure_summary(trend_st, confirm_st, entry_st, adx_row)
        h1 = trend_st[:direction]&.to_s
        m15 = confirm_st[:direction]&.to_s
        m5 = entry_st[:direction]&.to_s
        adx = adx_row[:adx]
        plus_di = adx_row[:plus_di]
        minus_di = adx_row[:minus_di]

        aligned_bull = h1 == "bullish" && m15 == "bullish" && m5 == "bullish"
        aligned_bear = h1 == "bearish" && m15 == "bearish" && m5 == "bearish"
        bias =
          if aligned_bull
            "bullish_aligned"
          elsif aligned_bear
            "bearish_aligned"
          else
            "mixed"
          end

        {
          bias: bias,
          h1: h1,
          m15: m15,
          m5: m5,
          adx: adx&.round(2),
          plus_di: plus_di&.round(2),
          minus_di: minus_di&.round(2),
          adx_threshold: @config.adx_threshold.to_f,
          trending: adx.present? && adx >= @config.adx_threshold
        }
      end
    end
  end
end
