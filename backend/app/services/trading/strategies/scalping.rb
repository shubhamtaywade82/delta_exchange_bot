# frozen_string_literal: true

module Trading
  module Strategies
    # Scalping strategy reacts to short-term imbalance pressure.
    class Scalping
      # @param book [Trading::Orderbook::Book]
      # @param features [Hash]
      # @param config [Hash]
      # @return [Symbol]
      def self.call(book:, features:, config:)
        threshold = 0.3 * config.fetch("aggression", 0.5).to_f
        return :buy if features[:imbalance].to_f > threshold
        return :sell if features[:imbalance].to_f < -threshold

        :hold
      end
    end
  end
end
