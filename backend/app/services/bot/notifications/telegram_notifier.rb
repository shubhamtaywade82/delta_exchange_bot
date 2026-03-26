# frozen_string_literal: true

require "telegram/bot"

module Bot
  module Notifications
    class TelegramNotifier
      def initialize(enabled:, token:, chat_id:, logger: nil)
        @enabled = enabled
        @token   = token
        @chat_id = chat_id.to_s
        @logger  = logger
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

      def client
        @client ||= Telegram::Bot::Client.new(@token)
      end
    end
  end
end
