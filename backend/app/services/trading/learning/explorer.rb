# frozen_string_literal: true

module Trading
  module Learning
    # Explorer selects strategies via epsilon-greedy exploration.
    class Explorer
      EPSILON = ENV.fetch("LEARNING_EPSILON", 0.05).to_f

      # @param strategies [Array<String>]
      # @param scores [Hash{String=>Numeric}]
      # @return [String]
      def self.choose(strategies, scores)
        return strategies.sample if rand < EPSILON

        strategies.max_by { |strategy| scores[strategy].to_f }
      end
    end
  end
end
