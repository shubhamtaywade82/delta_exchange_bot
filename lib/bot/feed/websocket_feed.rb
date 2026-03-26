# frozen_string_literal: true

require "delta_exchange"
require_relative "delta_ws_patch"

module Bot
  module Feed
    class WebsocketFeed
      def initialize(symbols:, price_store:, logger:, testnet: false, on_tick: nil)
        @symbols     = symbols
        @price_store = price_store
        @logger      = logger
        @testnet     = testnet
        @on_tick     = on_tick
        @client      = nil
        @running     = false
        @generation  = 0
      end

      def start
        # Ensure EventMachine is running in its own thread
        unless EM.reactor_running?
          Thread.new { EM.run }
          sleep 0.1 until EM.reactor_running?
        end

        # Close the previous Faye WS directly (avoids calling connection.stop
        # which would halt the whole EM reactor).
        if @client
          prev_ws = @client.instance_variable_get(:@connection)
                           &.instance_variable_get(:@ws)
          prev_ws&.close
        end

        @running    = true
        @generation += 1
        gen          = @generation   # captured in closures below

        EM.next_tick do
          @client = DeltaExchange::Websocket::Client.new(testnet: @testnet)

          @client.on(:open) do
            @logger.info("ws_connected")
            # Delta Exchange India v2/ticker requires a single channel entry
            # with a "symbols" array — NOT one entry per symbol.
            @client.subscribe([{ name: "v2/ticker", symbols: @symbols }])
          end

          @client.on(:message) do |data|
            @logger.debug("ws_message_received", raw: data.is_a?(Hash) ? data : data.to_s)
            next unless data.is_a?(Hash)

            case data["type"]
            when "key-auth"
              if data["success"]
                @logger.info("ws_authenticated")
              else
                @logger.error("ws_auth_failed", message: data["message"])
                @client.close
                @running = false if @generation == gen
              end
            when "v2/ticker"
              symbol = data["symbol"]
              price  = data["mark_price"]&.to_f || data["close"]&.to_f
              if symbol && price && price.positive?
                @price_store.update(symbol, price)
                @logger.debug("ltp_update", symbol: symbol, price: price)
                @on_tick&.call(symbol, price, Time.now.to_i)
              end
            when "subscriptions"
              @logger.info("ws_subscribed", channels: data["channels"])
            end
          end

          @client.on(:close) do |event|
            # Only treat this as a disconnect if it belongs to the current
            # generation — stale callbacks from a previous client must not
            # kill the running thread.
            next unless @generation == gen

            @logger.warn("ws_disconnected", code: event.code, reason: event.reason)
            @running = false
          end

          @client.on(:error) do |err|
            next unless @generation == gen

            @logger.error("ws_error", message: err.to_s)
            @running = false
          end

          @client.connect!
        end

        # Keep this thread alive as long as the supervisor wants this 'service' to run
        sleep 1 while @running
      end

      def stop
        @running = false
        @client&.close
      end
    end
  end
end
