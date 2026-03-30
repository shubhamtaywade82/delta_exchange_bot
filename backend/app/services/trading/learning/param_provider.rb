# frozen_string_literal: true

module Trading
  module Learning
    # ParamProvider returns online-learned parameters for strategy/regime pair.
    class ParamProvider
      Default = Struct.new(:aggression, :risk_multiplier, :bias, keyword_init: true)

      # @param strategy [String]
      # @param regime [String, Symbol]
      # @return [StrategyParam, Default]
      def self.fetch(strategy:, regime:)
        StrategyParam.find_by(strategy: strategy, regime: regime.to_s) || default
      end

      def self.default
        Default.new(aggression: 0.5.to_d, risk_multiplier: 1.0.to_d, bias: 0.to_d)
      end
    end
  end
end
