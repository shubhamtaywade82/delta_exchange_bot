# frozen_string_literal: true

module PaperTrading
  # Matches one paper order against current order book levels and returns executable fills.
  class MatchingEngine
    def initialize(order_book:)
      @order_book = order_book
    end

    # @param order [PaperOrder]
    # @return [Array<Hash>] [{ price:, qty:, liquidity: }]
    def execute(order)
      return match_market(order) if market_order?(order)

      match_limit(order)
    end

    private

    def market_order?(order)
      order.order_type.to_s == "market_order"
    end

    def match_market(order)
      remaining = order.size.to_d
      levels = executable_levels(order)
      fills = []

      levels.each do |price, level_qty|
        break unless remaining.positive?

        fill_qty = [ remaining, level_qty ].min
        fills << build_fill(price: price, qty: fill_qty, liquidity: :taker)
        remaining -= fill_qty
      end

      fills
    end

    def match_limit(order)
      return [] unless crosses_spread?(order)

      match_market(order)
    end

    def crosses_spread?(order)
      if buy_side?(order)
        ask = @order_book.best_ask
        return false if ask.blank?

        order.limit_price.to_d >= ask.first
      else
        bid = @order_book.best_bid
        return false if bid.blank?

        order.limit_price.to_d <= bid.first
      end
    end

    def executable_levels(order)
      buy_side?(order) ? @order_book.asks : @order_book.bids
    end

    def buy_side?(order)
      order.side.to_s == "buy"
    end

    def build_fill(price:, qty:, liquidity:)
      {
        price: price,
        qty: qty.to_i,
        liquidity: liquidity
      }
    end
  end
end
