# frozen_string_literal: true

module Trading
  module Analysis
    # Which SMC entry templates are structurally “open” on this timeframe (flags only).
    module SmcEntryContext
      extend self

      def flags(snap_hash, last_close)
        close = last_close.to_f
        obs = snap_hash["order_blocks"] || []
        fvgs = snap_hash["fair_value_gaps"] || []
        liq = snap_hash["liquidity"]

        {
          "ob_mitigation_in_play" => obs.any? { |o| %w[partial unfilled].include?(o.dig("mitigation", "state")) },
          "fvg_unfilled_or_partial" => fvgs.any? { |f| %w[partial unfilled].include?(f.dig("mitigation", "state")) },
          "liquidity_sweep_recent" => liq.is_a?(Hash),
          "price_near_nearest_ob_edge" => near_ob_edge?(obs, close),
          "price_inside_nearest_fvg" => inside_fvg?(fvgs, close)
        }
      end

      def near_ob_edge?(obs, close, tolerance_pct: 0.12)
        return false if obs.empty?

        ob = obs.last
        lo = ob["low"].to_f
        hi = ob["high"].to_f
        mid = (lo + hi) / 2.0
        span = hi - lo
        tol = [span * (tolerance_pct / 100.0), close.abs * (tolerance_pct / 100.0)].max
        (close - lo).abs <= tol || (close - hi).abs <= tol || (close - mid).abs <= (span / 4.0)
      end

      def inside_fvg?(fvgs, close)
        fvgs.any? do |f|
          bot = [f["low"].to_f, f["high"].to_f].min
          top = [f["low"].to_f, f["high"].to_f].max
          close >= bot && close <= top
        end
      end
    end
  end
end
