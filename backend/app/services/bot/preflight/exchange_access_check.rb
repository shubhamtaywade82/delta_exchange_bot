# frozen_string_literal: true

module Bot
  module Preflight
    class ExchangeAccessCheck
      CATEGORY_BY_BROKER_CODE = {
        "ip_not_whitelisted_for_api_key" => "auth_whitelist",
        "expired_signature" => "signature_time_skew"
      }.freeze

      def self.call
        new.call
      end

      def call
        DeltaExchange::Models::WalletBalance.find_by_asset("USD")
        { healthy: true, category: "ok", message: "exchange access healthy", broker_code: nil }
      rescue StandardError => e
        category, broker_code = classify(e.message)
        {
          healthy: false,
          category: category,
          message: e.message,
          broker_code: broker_code
        }
      end

      private

      def classify(message)
        broker_code = message.to_s[/\"code\"=>\"([^\"]+)\"/, 1]
        category = CATEGORY_BY_BROKER_CODE.fetch(broker_code, "unknown")
        [category, broker_code]
      end
    end
  end
end
