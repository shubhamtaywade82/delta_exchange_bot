# frozen_string_literal: true

require "delta_exchange"

module Bot
  module Account
    class CapitalManager
      def initialize(usd_to_inr_rate:)
        @usd_to_inr_rate = usd_to_inr_rate
      end

      def available_usdt
        balance = DeltaExchange::Models::WalletBalance.find_by_asset("USDT")
        balance&.available_balance.to_f
      end

      def available_inr
        available_usdt * @usd_to_inr_rate
      end
    end
  end
end
