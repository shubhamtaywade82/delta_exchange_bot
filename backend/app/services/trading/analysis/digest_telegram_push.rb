# frozen_string_literal: true

module Trading
  module Analysis
    # Sends `ai_insight` (Ollama summary) to Telegram in HTML-safe chunks after a digest row is built.
    class DigestTelegramPush
      def self.deliver_row(row)
        new(row).deliver
      end

      def initialize(row)
        @row = row.is_a?(Hash) ? row.deep_stringify_keys : {}
      end

      def deliver
        body = extract_plain_text
        return if body.blank?

        symbol = @row["symbol"].to_s.strip
        return if symbol.empty?

        Trading::TelegramNotifications.deliver do |notifier|
          notifier.notify_smc_analysis_digest(symbol: symbol, plain_text: body)
        end
      end

      private

      def extract_plain_text
        return nil if @row["error"].present?

        insight = @row["ai_insight"].to_s.strip.presence
        return insight if insight.present?

        ai = @row["ai_smc"]
        return nil unless ai.is_a?(Hash)

        ai["summary"].to_s.strip.presence
      end
    end
  end
end
