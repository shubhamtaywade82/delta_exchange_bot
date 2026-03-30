# frozen_string_literal: true

module Trading
  module Strategy
    # RegimeDetector classifies market regime using deterministic feature thresholds.
    class RegimeDetector
      # @param features [Hash]
      # @return [Symbol]
      def self.call(features)
        if features[:volatility].to_f > ENV.fetch("REGIME_VOLATILITY_THRESHOLD", 50).to_f &&
           features[:spread].to_f > ENV.fetch("REGIME_SPREAD_THRESHOLD", 1).to_f
          :high_volatility
        elsif features[:imbalance].to_f.abs > ENV.fetch("REGIME_IMBALANCE_THRESHOLD", 0.4).to_f
          :trending
        else
          :mean_reversion
        end
      end
    end
  end
end
