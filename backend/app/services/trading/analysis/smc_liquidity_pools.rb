# frozen_string_literal: true

module Trading
  module Analysis
    # Equal highs / equal lows (EQH/EQL) and recent swing liquidity levels.
    module SmcLiquidityPools
      EQH_TOLERANCE_PCT = Float(ENV.fetch("ANALYSIS_EQH_TOLERANCE_PCT", "0.08"))
      MAX_SWING_LEVELS = Integer(ENV.fetch("ANALYSIS_SWING_LIQUIDITY_LEVELS", "8"))

      extend self

      def analyze(candles, swing: 3)
        return default_empty if candles.size < swing * 4

        highs = Bot::Strategy::Indicators::SwingFractal.pivot_high_indices(candles, left: swing, right: swing)
        lows = Bot::Strategy::Indicators::SwingFractal.pivot_low_indices(candles, left: swing, right: swing)
        high_prices = highs.map { |i| candles[i][:high].to_f }
        low_prices = lows.map { |i| candles[i][:low].to_f }

        {
          "equal_high_clusters" => cluster_equal_prices(high_prices, EQH_TOLERANCE_PCT),
          "equal_low_clusters" => cluster_equal_prices(low_prices, EQH_TOLERANCE_PCT),
          "swing_high_liquidity" => high_prices.last(MAX_SWING_LEVELS),
          "swing_low_liquidity" => low_prices.last(MAX_SWING_LEVELS)
        }
      end

      def default_empty
        {
          "equal_high_clusters" => [],
          "equal_low_clusters" => [],
          "swing_high_liquidity" => [],
          "swing_low_liquidity" => []
        }
      end

      def cluster_equal_prices(prices, tolerance_pct)
        return [] if prices.empty?

        sorted = prices.sort
        clusters = []
        sorted.each do |p|
          cluster = clusters.find { |c| price_near?(c["center"], p, tolerance_pct) }
          if cluster
            cluster["members"] << p
            cluster["center"] = (cluster["members"].sum / cluster["members"].size).round(8)
            cluster["count"] = cluster["members"].size
          else
            clusters << { "center" => p.round(8), "members" => [p], "count" => 1 }
          end
        end
        clusters.select { |c| c["count"] >= 2 }.sort_by { |c| -c["count"] }.first(5)
      end

      def price_near?(a, b, tolerance_pct)
        denom = [a.abs, b.abs, 1.0].max
        (a - b).abs / denom * 100.0 <= tolerance_pct
      end
    end
  end
end
