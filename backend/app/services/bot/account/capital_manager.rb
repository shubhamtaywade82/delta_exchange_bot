# frozen_string_literal: true


module Bot
  module Account
    class CapitalManager
      attr_reader :usd_to_inr_rate

      DRY_RUN_SIMULATED_CAPITAL_USD = 10_000.0

      def initialize(usd_to_inr_rate:, dry_run: false)
        @usd_to_inr_rate = usd_to_inr_rate
        @dry_run         = dry_run
      end

      def available_usdt
        # Delta Exchange India uses "USD" as the margin asset for USD-settled
        # perpetuals; try USDT first then fall back to USD.
        balance = DeltaExchange::Models::WalletBalance.find_by_asset("USDT") ||
                  DeltaExchange::Models::WalletBalance.find_by_asset("USD")
        result = balance&.available_balance.to_f || 0.0
        # In dry_run mode use simulated capital when real balance is too small to trade
        @dry_run && result < 1.0 ? DRY_RUN_SIMULATED_CAPITAL_USD : result
      end

      def available_inr
        available_usdt * @usd_to_inr_rate
      end
    end
  end
end
