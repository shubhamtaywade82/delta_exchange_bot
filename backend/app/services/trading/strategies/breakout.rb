# frozen_string_literal: true

module Trading
  module Strategies
    # Breakout strategy takes liquidity when spread and momentum confirm a move.
    class Breakout
      # @param book [Trading::Orderbook::Book]
      # @param features [Hash]
      # @param config [Hash]
      # @return [Symbol]
      def self.call(book:, features:, config:)
        min_spread = ENV.fetch("BREAKOUT_MIN_SPREAD", 0.5).to_f
        return :hold if book.spread.to_f < min_spread

        return :buy if features[:momentum].to_f.positive?
        return :sell if features[:momentum].to_f.negative?

        :hold
      end
    end
  end
end
