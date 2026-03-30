# frozen_string_literal: true

module Trading
  module Execution
    # BatchExecutor sends capped order batches to exchange adapter.
    class BatchExecutor
      MAX_BATCH = 50

      # @param orders [Array<Hash>]
      # @param client [Object]
      # @return [Object]
      def self.place!(orders, client:)
        raise ArgumentError, "Max 50 orders" if orders.size > MAX_BATCH

        client.batch_orders(orders)
      end
    end
  end
end
