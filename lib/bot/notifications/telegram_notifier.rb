# frozen_string_literal: true

require "telegram/bot"

module Bot
  module Notifications
    class TelegramNotifier
      def initialize(enabled:, token:, chat_id:)
        @enabled = enabled
        @token   = token
        @chat_id = chat_id.to_s
      end

      def send_message(text)
        return unless @enabled && !@token.to_s.empty?

        client.api.send_message(chat_id: @chat_id, text: text, parse_mode: "HTML")
      rescue StandardError => e
        warn "[TelegramNotifier] Failed to send: #{e.message}"
      end

      private

      def client
        @client ||= Telegram::Bot::Client.new(@token)
      end
    end
  end
end
