# frozen_string_literal: true

module Trading
  module Execution
    # DecisionEngine chooses maker/taker execution per microstructure state.
    class DecisionEngine
      # @param signal [Symbol]
      # @param book [Trading::Orderbook::Book]
      # @return [Symbol]
      def self.call(signal:, book:)
        spread = book.spread.to_f
        return :no_trade if spread <= 0

        imbalance = Trading::Microstructure::Imbalance.calculate(book)

        return :taker_buy if signal == :long && imbalance > 0.4
        return :taker_sell if signal == :short && imbalance < -0.4

        return :maker_buy if signal == :long
        return :maker_sell if signal == :short

        :no_trade
      end
    end
  end
end
