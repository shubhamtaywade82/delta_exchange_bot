# frozen_string_literal: true

require "eventmachine"

module Bot
  module Feed
    class WebsocketFeed
      def initialize(symbols:, price_store:, logger:, testnet: false, on_tick: nil, on_message: nil)
        @symbols     = symbols
        @price_store = price_store
        @logger      = logger
        @testnet     = testnet
        @on_tick     = on_tick
        @on_message  = on_message
        @client      = nil
        @running     = false
        @generation  = 0
      end

      def start
        @running = true
        @generation += 1
        gen = @generation

        unless ::EventMachine.reactor_running?
          Thread.new { ::EventMachine.run }
          sleep 0.1 until ::EventMachine.reactor_running?
        end

        ::EventMachine.next_tick do
          if @client
            @client.close rescue nil
            @client = nil
          end

          @client = DeltaExchange::Websocket::Client.new(testnet: @testnet)

          @client.on(:close) do |event|
            next unless @generation == gen
            @logger.warn("ws_disconnected", code: event.code, reason: event.reason)
            @running = false
          end

          @client.on(:error) do |err|
            next unless @generation == gen
            @logger.error("ws_error", message: err.to_s)
            @running = false
          end

          @client.on(:open) do
            @logger.info("ws_connected")
            @client.subscribe([{ name: "v2/ticker", symbols: @symbols }])
            @client.subscribe([{ name: "v2/orders", symbols: @symbols }])
            @client.subscribe([{ name: "v2/fills", symbols: @symbols }])
            @client.subscribe([{ name: "v2/orderbook", symbols: @symbols }])
          end

          @client.on(:message) do |data|
            @on_message&.call(data)

            next unless data.is_a?(Hash) && data["type"] == "v2/ticker"
            symbol = data["symbol"]
            price  = data["mark_price"]&.to_f || data["close"]&.to_f
            ts = Time.at((data["timestamp"] || Time.now.to_i).to_i)
            if symbol && price&.positive?
              @price_store.update(symbol, price)
              @on_tick&.call(symbol, price, ts)
            end
          end

          @client.connect!
        end

        sleep 1 while @running
      rescue StandardError => e
        @logger.error("ws_process_crash", message: e.message)
      ensure
        @running = false
      end

      def stop
        @running = false
        @client&.close
      end
    end
  end
end
