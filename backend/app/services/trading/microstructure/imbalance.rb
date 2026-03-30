# frozen_string_literal: true

module Trading
  module Microstructure
    # Imbalance computes top-of-book pressure.
    class Imbalance
      # @param book [Trading::Orderbook::Book]
      # @param depth [Integer]
      # @return [Float]
      def self.calculate(book, depth: 5)
        bids = book.bids.sort_by { |p, _| -p }.first(depth)
        asks = book.asks.sort_by { |p, _| p }.first(depth)

        bid_vol = bids.sum { |_, size| size.to_d }
        ask_vol = asks.sum { |_, size| size.to_d }

        total = bid_vol + ask_vol
        return 0.0 if total.zero?

        ((bid_vol - ask_vol) / total).to_f
      end
    end
  end
end
