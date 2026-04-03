# frozen_string_literal: true

require "telegram/bot"

module Bot
  module Notifications
    class TelegramNotifier
      def initialize(enabled:, token:, chat_id:, logger: nil, event_settings: {})
        @enabled = enabled
        @token   = token
        @chat_id = chat_id.to_s
        @logger  = logger
        @event_settings = event_settings || {}
      end

      def send_message(text)
        return unless @enabled && !@token.to_s.empty?

        client.api.send_message(chat_id: @chat_id, text: text, parse_mode: "HTML")
      rescue StandardError => e
        if @logger
          @logger.error("telegram_send_failed", message: e.message)
        else
          $stderr.puts("[TelegramNotifier] Failed to send: #{e.message}")
        end
      end

      private

      def enabled_for?(event)
        return false unless @enabled && !@token.to_s.empty?
        return true unless @event_settings.key?(event.to_sym)

        @event_settings[event.to_sym] == true
      end

      def client
        @client ||= Telegram::Bot::Client.new(@token)
      end

      public

      def notify_status(message, status: nil)
        return unless enabled_for?(:status)

        prefix = status ? "ℹ️ <b>#{status.upcase}</b>" : "ℹ️ <b>STATUS</b>"
        send_message("#{prefix}\n#{message}")
      end

      def notify_signal_generated(symbol:, side:, price:, strategy:)
        return unless enabled_for?(:signals)

        send_message("📡 <b>SIGNAL</b>\n#{symbol} #{side.to_s.upcase} via #{strategy}\nPrice: $#{format('%.2f', price)}")
      end

      def notify_trade_opened(symbol:, side:, price:, lots:, leverage:, trailing_stop:, mode:)
        return unless enabled_for?(:positions)

        emoji = side == :long ? "🟢" : "🔴"
        send_message(
          "#{emoji} <b>POSITION OPENED</b>\n" \
          "#{symbol} #{side.to_s.upcase} (#{mode})\n" \
          "Entry: $#{format('%.2f', price)}\n" \
          "Lots: #{lots} | Leverage: #{leverage}x\n" \
          "Trail Stop: $#{format('%.2f', trailing_stop)}"
        )
      end

      def notify_trailing_stop_triggered(symbol:, side:, ltp:, stop_price:)
        return unless enabled_for?(:trailing)

        send_message(
          "🧷 <b>TRAILING STOP HIT</b>\n" \
          "#{symbol} #{side.to_s.upcase}\n" \
          "LTP: $#{format('%.2f', ltp)}\n" \
          "Stop: $#{format('%.2f', stop_price)}"
        )
      end

      def notify_trade_closed(symbol:, exit_price:, pnl_usd:, pnl_inr:, duration_seconds:, reason:)
        return unless enabled_for?(:positions)

        sign  = pnl_usd >= 0 ? "+" : ""
        emoji = pnl_usd >= 0 ? "🟢" : "🔴"
        hours = duration_seconds / 3600
        mins  = (duration_seconds % 3600) / 60
        send_message(
          "#{emoji} <b>POSITION CLOSED</b>\n" \
          "#{symbol} — #{reason}\n" \
          "Exit: $#{format('%.2f', exit_price)}\n" \
          "PnL: #{sign}$#{format('%.2f', pnl_usd)} (#{sign}₹#{pnl_inr.round(0)})\n" \
          "Duration: #{hours}h #{mins}m"
        )
      end

      def notify_error(context:, message:)
        return unless enabled_for?(:errors)

        send_message("🚨 <b>ERROR</b>\n#{context}\n#{message}")
      end
    end
  end
end
