# frozen_string_literal: true

module PaperTrading
  # Stores and serves one symbol's sorted L2 levels for deterministic matching.
  class OrderBook
    attr_reader :bids, :asks

    def initialize
      @bids = []
      @asks = []
    end

    # @param snapshot [Hash] { bids: [[price, qty]], asks: [[price, qty]] }
    # @return [void]
    def update!(snapshot)
      @bids = normalize_levels(snapshot[:bids]).sort_by { |price, _qty| -price }
      @asks = normalize_levels(snapshot[:asks]).sort_by { |price, _qty| price }
    end

    # @return [Array(BigDecimal, BigDecimal), nil]
    def best_bid
      bids.first
    end

    # @return [Array(BigDecimal, BigDecimal), nil]
    def best_ask
      asks.first
    end

    private

    def normalize_levels(levels)
      Array(levels).filter_map do |level|
        price, quantity = level
        normalized_price = price.to_d
        normalized_quantity = quantity.to_d
        next unless normalized_price.positive? && normalized_quantity.positive?

        [ normalized_price, normalized_quantity ]
      end
    end
  end
end
