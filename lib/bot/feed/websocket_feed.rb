# frozen_string_literal: true

require "delta_exchange"

module Bot
  module Feed
    class WebsocketFeed
      def initialize(symbols:, price_store:, logger:, testnet: false)
        @symbols     = symbols
        @price_store = price_store
        @logger      = logger
        @testnet     = testnet
        @client      = nil
      end

      def start
        @client = DeltaExchange::Websocket::Client.new(testnet: @testnet)
        queue   = Queue.new

        @client.on(:open) do
          @logger.info("ws_connected")
          @client.subscribe([{ name: "v2/ticker", symbols: @symbols }])
        end

        @client.on(:message) do |data|
          next unless data.is_a?(Hash) && data["type"] == "v2/ticker"

          symbol = data["symbol"]
          price  = data["mark_price"]&.to_f || data["close"]&.to_f
          next unless symbol && price && price.positive?

          @price_store.update(symbol, price)
          @logger.debug("ltp_update", symbol: symbol, price: price)
        end

        @client.on(:close) do |event|
          @logger.warn("ws_disconnected", code: event.code, reason: event.reason)
          @client.close
          queue.push(:closed)
        end

        @client.on(:error) do |err|
          @logger.error("ws_error", message: err.to_s)
          @client.close
          queue.push(:error)
        end

        @client.connect!
        queue.pop # Block until closed or error
      end

      def stop
        @client&.close
      end
    end
  end
end
