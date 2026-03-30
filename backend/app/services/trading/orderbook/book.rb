# frozen_string_literal: true

module Trading
  module Orderbook
    # Book keeps an in-memory L2 snapshot for a symbol.
    class Book
      attr_reader :bids, :asks

      def initialize
        @bids = {}
        @asks = {}
      end

      # @param data [Hash]
      # @return [void]
      def update!(data)
        apply_side!(@bids, data[:bids] || [])
        apply_side!(@asks, data[:asks] || [])
      end

      def best_bid
        @bids.keys.max
      end

      def best_ask
        @asks.keys.min
      end

      def spread
        return 0.to_d if best_bid.nil? || best_ask.nil?

        best_ask.to_d - best_bid.to_d
      end

      private

      def apply_side!(levels, updates)
        updates.each do |price, size|
          p = price.to_d
          s = size.to_d
          if s.zero?
            levels.delete(p)
          else
            levels[p] = s
          end
        end
      end
    end
  end
end
