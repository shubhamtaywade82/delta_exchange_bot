# app/services/trading/bootstrap/sync_positions.rb
module Trading
  module Bootstrap
    class SyncPositions
      def self.call(client:)
        new(client).call
      end

      def initialize(client)
        @client = client
      end

      def call
        exchange_positions = @client.get_positions
        exchange_positions.each { |ep| upsert_position(ep) }
        close_stale_positions(exchange_positions)
        Rails.logger.info("[Bootstrap::SyncPositions] Synced #{exchange_positions.size} positions")
      rescue => e
        Rails.logger.error("[Bootstrap::SyncPositions] Failed: #{e.message}")
        raise
      end

      private

      def upsert_position(ep)
        position = Position.where(symbol: ep[:symbol]).where.not(status: %w[closed liquidated rejected]).first
        position ||= Position.new(symbol: ep[:symbol], portfolio: Portfolio.resolve_for_legacy_bot_execution!)
        position.status = "filled" if position.new_record?
        position.portfolio ||= Portfolio.resolve_for_legacy_bot_execution!
        position.assign_attributes(
          side:              ep[:side],
          size:              ep[:size],
          entry_price:       ep[:entry_price],
          leverage:          ep[:leverage],
          margin:            ep[:margin],
          liquidation_price: ep[:liquidation_price],
          product_id:        ep[:product_id]
        )
        position.save!
      end

      def close_stale_positions(exchange_positions)
        active_symbols = exchange_positions.map { |ep| ep[:symbol] }
        Position.active
                .where.not(symbol: active_symbols)
                .update_all(status: "closed")
      end
    end
  end
end
