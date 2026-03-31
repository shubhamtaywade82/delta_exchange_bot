# frozen_string_literal: true

module Trading
  module Strategy
    # RegimeDetector classifies market regime using deterministic feature thresholds.
    class RegimeDetector
      # @param features [Hash]
      # @return [Symbol]
      def self.call(features)
        volatility_threshold = Trading::RuntimeConfig.fetch_float("regime.volatility_threshold", default: 50.0, env_key: "REGIME_VOLATILITY_THRESHOLD")
        spread_threshold = Trading::RuntimeConfig.fetch_float("regime.spread_threshold", default: 1.0, env_key: "REGIME_SPREAD_THRESHOLD")
        imbalance_threshold = Trading::RuntimeConfig.fetch_float("regime.imbalance_threshold", default: 0.4, env_key: "REGIME_IMBALANCE_THRESHOLD")

        if features[:volatility].to_f > volatility_threshold &&
           features[:spread].to_f > spread_threshold
          :high_volatility
        elsif features[:imbalance].to_f.abs > imbalance_threshold
          :trending
        else
          :mean_reversion
        end
      end
    end
  end
end
