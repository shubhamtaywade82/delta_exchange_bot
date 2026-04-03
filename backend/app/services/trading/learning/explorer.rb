# frozen_string_literal: true

module Trading
  module Learning
    # Explorer selects strategies via epsilon-greedy exploration.
    class Explorer
      # @param strategies [Array<String>]
      # @param scores [Hash{String=>Numeric}]
      # @return [String]
      def self.choose(strategies, scores)
        epsilon = Trading::RuntimeConfig.fetch_float("learning.epsilon", default: 0.05, env_key: "LEARNING_EPSILON")
        return strategies.sample if rand < epsilon

        strategies.max_by { |strategy| scores[strategy].to_f }
      end
    end
  end
end
