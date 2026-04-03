# frozen_string_literal: true

module Trading
  module Analysis
    # One-timeframe SMC + PA bundle for Ollama and the analysis dashboard.
    class SmcSnapshot
      BOS_LOOKBACK = Integer(ENV.fetch("ANALYSIS_BOS_SWING_LOOKBACK", "10"))
      CHOCH_SWING = Integer(ENV.fetch("ANALYSIS_CHOCH_SWING", "3"))
      OB_MIN_IMPULSE_PCT = Float(ENV.fetch("ANALYSIS_OB_MIN_IMPULSE_PCT", "0.3"))
      OB_MAX_AGE = Integer(ENV.fetch("ANALYSIS_OB_MAX_AGE", "20"))
      FVG_MAX_AGE = Integer(ENV.fetch("ANALYSIS_FVG_MAX_AGE", "30"))
      SWEEP_LOOKBACK = Integer(ENV.fetch("ANALYSIS_SWEEP_LOOKBACK", "25"))

      def self.build(candles:, resolution:)
        new(candles: candles, resolution: resolution).to_h
      end

      def initialize(candles:, resolution:)
        @candles = candles
        @resolution = resolution
      end

      def to_h
        return insufficient if @candles.size < 5

        last_close = @candles.last[:close].to_f
        internal_lb = [BOS_LOOKBACK / 2, 3].max

        bos_series = Bot::Strategy::Indicators::BOS.compute(@candles, swing_lookback: BOS_LOOKBACK)
        bos = bos_series.last
        choch = Bot::Strategy::Indicators::Choch.last_event(@candles, swing: CHOCH_SWING)
        order_blocks = Bot::Strategy::Indicators::OrderBlock.compute(
          @candles,
          min_impulse_pct: OB_MIN_IMPULSE_PCT,
          max_ob_age: OB_MAX_AGE
        )
        fvgs = Bot::Strategy::Indicators::FairValueGap.detect(@candles, max_age: FVG_MAX_AGE)
        sweep = Bot::Strategy::Indicators::LiquiditySweep.recent(@candles, swing: CHOCH_SWING,
                                                                   lookback: SWEEP_LOOKBACK)

        structure_sequence = SmcSwingStructure.analyze(@candles, swing: CHOCH_SWING)
        internal_external = SmcInternalExternalStructure.snapshot(
          @candles,
          external_lookback: BOS_LOOKBACK,
          internal_lookback: internal_lb
        )
        liquidity_pools = SmcLiquidityPools.analyze(@candles, swing: CHOCH_SWING)
        premium_discount = SmcPremiumDiscount.position(@candles)
        sessions = SmcSessionRanges.snapshot(@candles)
        order_flow = SmcOrderFlowSnapshot.last_bar(@candles)
        price_action_classical = SmcPriceActionSnapshot.last_bar(@candles)
        volatility = SmcVolatilitySnapshot.snapshot(@candles)

        serialized_fvgs = fvgs.last(8).map { |f| serialize_fvg(f, last_close) }
        serialized_obs = order_blocks.last(8).map { |ob| serialize_ob(ob, last_close) }
        liq_h = serialize_liquidity(sweep)

        base = {
          "resolution" => @resolution,
          "structure_sequence" => structure_sequence,
          "internal_external_structure" => internal_external,
          "choch" => serialize_choch(choch),
          "bos" => serialize_bos(bos),
          "fair_value_gaps" => serialized_fvgs,
          "order_blocks" => serialized_obs,
          "liquidity" => liq_h,
          "liquidity_pools" => liquidity_pools,
          "premium_discount" => premium_discount,
          "session_liquidity_ranges" => sessions,
          "order_flow" => order_flow,
          "price_action_classical" => price_action_classical,
          "volatility" => volatility,
          "bias_hint" => bias_hint(bos, choch)
        }

        base["inducement_traps_hints"] = inducement_traps_hints(internal_external, base["choch"], base["bos"])
        base["entry_model_flags"] = SmcEntryContext.flags(base, last_close)
        base
      end

      private

      def insufficient
        {
          "resolution" => @resolution,
          "error" => "insufficient_candles",
          "structure_sequence" => SmcSwingStructure.default_empty,
          "internal_external_structure" => nil,
          "choch" => nil,
          "bos" => nil,
          "fair_value_gaps" => [],
          "order_blocks" => [],
          "liquidity" => nil,
          "liquidity_pools" => SmcLiquidityPools.default_empty,
          "premium_discount" => nil,
          "session_liquidity_ranges" => {},
          "order_flow" => nil,
          "price_action_classical" => nil,
          "volatility" => nil,
          "bias_hint" => nil,
          "inducement_traps_hints" => [],
          "entry_model_flags" => {}
        }
      end

      def inducement_traps_hints(ie, choch_h, bos_h)
        hints = []
        hints << "internal_vs_external_bos_divergent" if ie.is_a?(Hash) && ie["divergent"]
        if choch_h.is_a?(Hash) && bos_h.is_a?(Hash) &&
           choch_h["direction"].present? && bos_h["direction"].present? &&
           choch_h["direction"] != bos_h["direction"]
          hints << "choch_direction_differs_from_bos"
        end
        hints
      end

      def serialize_bos(bos)
        return nil unless bos

        {
          "direction" => bos[:direction]&.to_s,
          "level" => bos[:level],
          "confirmed" => bos[:confirmed]
        }
      end

      def serialize_choch(choch)
        return nil unless choch

        {
          "direction" => choch[:direction].to_s,
          "level" => choch[:level]
        }
      end

      def serialize_fvg(fvg, last_close)
        bottom = [fvg[:bottom], fvg[:top]].min
        top = [fvg[:bottom], fvg[:top]].max
        mit = mitigate_linear(last_close, bottom, top)

        {
          "type" => fvg[:type].to_s,
          "low" => bottom,
          "high" => top,
          "age_bars" => fvg[:age_bars],
          "mitigation" => mit.transform_keys(&:to_s),
          "inverse_role_candidate" => inverse_fvg_candidate?(fvg[:type], last_close, bottom, top, mit)
        }
      end

      def inverse_fvg_candidate?(ftype, close, bottom, top, mit)
        return false unless mit[:state].to_s == "filled"

        mid = (bottom + top) / 2.0
        if ftype.to_s == "bullish"
          close < mid
        else
          close > mid
        end
      end

      def serialize_ob(ob, last_close)
        low = ob[:low].to_f
        high = ob[:high].to_f
        mit = mitigate_linear(last_close, low, high)

        {
          "side" => ob[:side].to_s,
          "high" => high,
          "low" => low,
          "age_bars" => ob[:age],
          "fresh" => ob[:fresh],
          "strength_pct" => ob[:strength],
          "mitigation" => mit.transform_keys(&:to_s),
          "displacement_qualified" => ob[:strength].to_f >= OB_MIN_IMPULSE_PCT
        }
      end

      def mitigate_linear(close, zone_low, zone_high)
        return { state: "unknown", pct: 0.0 } if zone_high <= zone_low

        if close <= zone_low
          { state: "unfilled", pct: 0.0 }
        elsif close >= zone_high
          { state: "filled", pct: 100.0 }
        else
          { state: "partial", pct: ((close - zone_low) / (zone_high - zone_low) * 100).round(1) }
        end
      end

      def serialize_liquidity(sweep)
        return nil unless sweep

        {
          "side" => sweep[:side].to_s,
          "level" => sweep[:level],
          "interpretation" => sweep[:interpretation].to_s,
          "wick_penetration_ratio" => sweep[:wick_penetration_ratio],
          "close_rejection_depth_ratio" => sweep[:close_rejection_depth_ratio],
          "event_style" => sweep[:event_style].to_s
        }
      end

      def bias_hint(bos, choch)
        b = bos&.dig(:direction)&.to_s
        c = choch&.dig(:direction)&.to_s
        return "mixed" if b.blank? && c.blank?

        if b == "bullish" && c == "bullish"
          "bullish"
        elsif b == "bearish" && c == "bearish"
          "bearish"
        elsif b != c && b.present? && c.present?
          "conflicted"
        else
          b.presence || c.presence || "mixed"
        end
      end
    end
  end
end
