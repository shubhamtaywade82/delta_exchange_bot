# frozen_string_literal: true

module Trading
  module MarketData
    class WsClient
      INTERVAL_SECONDS = 60  # 1-minute candles

      def initialize(client:, symbols: nil, testnet: false)
        @client          = client
        @symbols         = symbols || SymbolConfig.where(enabled: true).pluck(:symbol)
        @testnet         = testnet
        @candle_builders = build_candle_builders
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
        Rails.cache.write("ltp:#{symbol}", price, expires_in: 30.seconds)

        EventBus.publish(
          :tick_received,
          Events::TickReceived.new(symbol: symbol, price: price, timestamp: timestamp, volume: 0.0)
        )

        closed_candle = @candle_builders[symbol]&.on_tick(price: price, timestamp: timestamp)
        if closed_candle
          CandleSeries.add(closed_candle)
          EventBus.publish(:candle_closed, closed_candle)
        end
      end

      def build_candle_builders
        @symbols.each_with_object({}) do |symbol, hash|
          hash[symbol] = CandleBuilder.new(symbol: symbol, interval_seconds: INTERVAL_SECONDS)
        end
      end
    end
  end
end
