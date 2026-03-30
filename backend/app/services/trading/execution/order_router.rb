# frozen_string_literal: true

module Trading
  module Execution
    # OrderRouter maps execution decisions to exchange order requests.
    class OrderRouter
      @rate_limiter = RateLimiter.new

      class << self
        # @param decision [Symbol]
        # @param book [Trading::Orderbook::Book]
        # @param qty [Numeric]
        # @param client [Object]
        # @return [Object, nil]
        def place!(decision:, book:, qty:, client:)
          return nil unless @rate_limiter.allow?

          case decision
          when :maker_buy
            place_limit(client: client, side: :buy, price: book.best_bid, qty: qty, post_only: true, reduce_only: false)
          when :maker_sell
            place_limit(client: client, side: :sell, price: book.best_ask, qty: qty, post_only: true, reduce_only: false)
          when :taker_buy
            place_market(client: client, side: :buy, qty: qty, reduce_only: false)
          when :taker_sell
            place_market(client: client, side: :sell, qty: qty, reduce_only: false)
          else
            nil
          end
        end

        def place_limit(client:, side:, price:, qty:, post_only:, reduce_only:)
          client.place_order(
            side: side.to_s,
            size: qty,
            price: price,
            order_type: "limit_order",
            post_only: post_only,
            reduce_only: reduce_only
          )
        end

        def place_market(client:, side:, qty:, reduce_only:)
          client.place_order(
            side: side.to_s,
            size: qty,
            order_type: "market_order",
            reduce_only: reduce_only
          )
        end
      end
    end
  end
end
