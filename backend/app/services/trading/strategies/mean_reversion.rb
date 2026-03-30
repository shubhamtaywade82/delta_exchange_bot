# frozen_string_literal: true

module Trading
  module Strategies
    # MeanReversion strategy fades extreme imbalance.
    class MeanReversion
      # @param book [Trading::Orderbook::Book]
      # @param features [Hash]
      # @param config [Hash]
      # @return [Symbol]
      def self.call(book:, features:, config:)
        threshold = ENV.fetch("MEAN_REV_IMBALANCE_THRESHOLD", 0.45).to_f
        return :sell if features[:imbalance].to_f > threshold
        return :buy if features[:imbalance].to_f < -threshold

        :hold
      end
    end
  end
end
