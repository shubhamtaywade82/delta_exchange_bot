# app/services/trading/bootstrap/sync_orders.rb
module Trading
  module Bootstrap
    class SyncOrders
      def self.call(client:, session:)
        new(client, session).call
      end

      def initialize(client, session)
        @client  = client
        @session = session
      end

      def call
        open_exchange_ids = fetch_open_exchange_order_ids
        cancel_stale_local_orders(open_exchange_ids)
        Rails.logger.info("[Bootstrap::SyncOrders] Cancelled stale orders not found on exchange")
      rescue => e
        Rails.logger.error("[Bootstrap::SyncOrders] Failed: #{e.message}")
        raise
      end

      private

      def fetch_open_exchange_order_ids
        @client.get_open_orders.map { |o| o[:id].to_s }
      rescue => e
        Rails.logger.warn("[Bootstrap::SyncOrders] Could not fetch open orders: #{e.message}")
        []
      end

      def cancel_stale_local_orders(open_exchange_ids)
        Order.where(trading_session: @session, status: %w[created submitted partially_filled])
             .where.not(exchange_order_id: open_exchange_ids)
             .update_all(status: "cancelled")
      end
    end
  end
end
