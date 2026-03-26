# frozen_string_literal: true


module DeltaExchange
  module Websocket
    class Connection
      # Override start so that when EM is already running on another thread,
      # setup_ws is scheduled ON the reactor thread (Faye::WebSocket::Client
      # must be created from within EventMachine).  When EM is not running we
      # fall through to the original loop_run thread which calls EM.run.
      def start
        if EM.reactor_running?
          EM.schedule { setup_ws }
        else
          @thr = Thread.new { loop_run }
        end
      end

      # Override to support custom WS URL from env
      def setup_ws
        # Use DELTA_WS_URL from environment if available
        ws_url = ENV.fetch("DELTA_WS_URL", @url)
        headers = { "User-Agent" => DeltaExchange.configuration.user_agent }
        
        DeltaExchange.logger.info("[DeltaExchange::WS] Connecting to #{ws_url}")
        @ws = Faye::WebSocket::Client.new(ws_url, nil, { headers: headers })

        @ws.on :open do |event|
          DeltaExchange.logger.info("[DeltaExchange::WS] Connected")
          # Only authenticate if we have a non-dummy key
          if @api_key && !@api_key.empty? && @api_key != "dummy" && @api_secret && !@api_secret.empty?
            authenticate!
          else
            DeltaExchange.logger.info("[DeltaExchange::WS] Skipping auth (dummy or missing key)")
          end
          start_heartbeat
          @on_open&.call(event)
        end

        @ws.on :message do |event|
          data = begin
            JSON.parse(event.data)
          rescue StandardError
            event.data
          end
          @on_message&.call(data)
        end

        @ws.on :close do |event|
          DeltaExchange.logger.warn("[DeltaExchange::WS] Closed: #{event.code} #{event.reason}")
          stop_heartbeat
          @on_close&.call(event)
          EM.stop unless EM.reactor_running?
        end

        @ws.on :error do |event|
          DeltaExchange.logger.error("[DeltaExchange::WS] Error: #{event.message}")
          @on_error&.call(event)
        end
      end

      # Override to use "key-auth" and correct signature format
      def authenticate!
        timestamp = Time.now.to_i
        # For Delta India /live endpoint authentication
        path = "/live"
        method = "GET"
        signature = Auth.sign(method, timestamp.to_s, path, "", "", @api_secret)

        DeltaExchange.logger.info("[DeltaExchange::WS] Sending key-auth (India)")
        send_json({
          type: "key-auth",
          payload: {
            "api-key": @api_key,
            signature: signature,
            timestamp: timestamp
          }
        })
      end

      private

      def start_heartbeat
        stop_heartbeat
        @heartbeat_timer = EventMachine.add_periodic_timer(15) do
          send_json({ type: "ping" })
        end
      end

      def stop_heartbeat
        EventMachine.cancel_timer(@heartbeat_timer) if @heartbeat_timer
        @heartbeat_timer = nil
      end
    end
  end
end
