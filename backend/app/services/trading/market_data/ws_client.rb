# frozen_string_literal: true

module Trading
  module MarketData
    class WsClient
      def initialize(client:, symbols: nil, testnet: false)
        @client          = client
        @symbols         = symbols || SymbolConfig.where(enabled: true).pluck(:symbol)
        @testnet         = testnet
        @price_store     = Bot::Feed::PriceStore.new
      end

      def start
        feed = Bot::Feed::WebsocketFeed.new(
          symbols:     @symbols,
          price_store: @price_store,
          logger:      Rails.logger,
          testnet:     @testnet,
          on_tick:     method(:handle_tick)
        )
        feed.start
      rescue => e
        Rails.logger.error("[WsClient] Feed crashed: #{e.message}")
        raise
      end

      private

      def handle_tick(symbol, price, timestamp)
        # Cache for quick access by the Runner and API
        Rails.cache.write("ltp:#{symbol}", price, expires_in: 30.seconds)

        # Publish for any real-time subscribers (like ActionCable)
        EventBus.publish(
          :tick_received,
          Events::TickReceived.new(symbol: symbol, price: price, timestamp: timestamp, volume: 0.0)
        )
      end
    end
  end
end
