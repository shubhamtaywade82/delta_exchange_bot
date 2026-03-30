# frozen_string_literal: true

module Trading
  module Execution
    # QueuePosition estimates resting size ahead at a target level.
    class QueuePosition
      # @param book [Trading::Orderbook::Book]
      # @param side [Symbol]
      # @param price [Numeric]
      # @return [BigDecimal]
      def self.estimate(book:, side:, price:)
        levels = if side == :buy
                   book.bids.select { |p, _| p >= price.to_d }
                 else
                   book.asks.select { |p, _| p <= price.to_d }
                 end

        levels.sum { |_, size| size.to_d }
      end
    end
  end
end
