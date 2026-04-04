# frozen_string_literal: true

module Bot
  module Notifications
    # Splits plain text for Telegram's 4096-character message limit (character count).
    class TelegramTextChunker
      TELEGRAM_MESSAGE_MAX_CHARS = 4096

      def self.chunk(plain_text, max_body_chars:)
        text = plain_text.to_s
        return [] if text.empty?

        max_body_chars = max_body_chars.to_i
        return [ text ] if max_body_chars <= 0
        return [ text ] if text.length <= max_body_chars

        chunks = []
        i = 0
        while i < text.length
          remaining = text.length - i
          take = [ max_body_chars, remaining ].min

          if take >= remaining
            tail = text[i..].rstrip
            chunks << tail if tail.present?
            break
          end

          segment = text[i, take]
          br = segment.rindex("\n\n")
          br ||= segment.rindex("\n")
          br = nil if br && br < take / 2
          slice_len = br || take
          slice_len = 1 if slice_len <= 0

          piece = text[i, slice_len].rstrip
          chunks << piece if piece.present?
          i += slice_len
          i += 1 while i < text.length && text[i] == "\n"
        end

        chunks
      end
    end
  end
end
