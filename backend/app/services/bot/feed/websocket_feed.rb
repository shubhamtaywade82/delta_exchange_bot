# frozen_string_literal: true

require "eventmachine"

module Bot
  module Feed
    class WebsocketFeed
      def initialize(symbols:, price_store:, logger:, testnet: false)
        @symbols     = symbols
        @price_store = price_store
        @logger      = logger
        @testnet     = testnet
        @client      = nil
        @running     = false
        @generation  = 0
      end

      def start
        @running = true
        @generation += 1
        gen = @generation

        # Ensure reactor is running
        unless ::EventMachine.reactor_running?
          Thread.new { ::EventMachine.run }
          sleep 0.1 until ::EventMachine.reactor_running?
        end

        ::EventMachine.next_tick do
          # Double-ensure old client is truly destroyed
          if @client 
             @client.close rescue nil
             @client = nil
          end

          @client = DeltaExchange::Websocket::Client.new(testnet: @testnet)
          
          # Force a clean disconnect on this gen's end
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
          end

          @client.on(:message) do |data|
            next unless data.is_a?(Hash) && data["type"] == "v2/ticker"
            symbol = data["symbol"]
            price  = data["mark_price"]&.to_f || data["close"]&.to_f
            @price_store.update(symbol, price) if symbol && price&.positive?
          end

          @client.connect!
        end

        # This thread must block until the connection is dead, 
        # allowing the supervisor to see the failure and back off.
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
