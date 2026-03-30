# frozen_string_literal: true

require "delta_exchange"

module Bot
  module Account
    class CapitalManager
      attr_reader :usd_to_inr_rate

      DEFAULT_DRY_RUN_CAPITAL_USD = 10_000.0

      def initialize(usd_to_inr_rate:, dry_run: false, paper_capital_inr: nil)
        @usd_to_inr_rate      = usd_to_inr_rate
        @dry_run              = dry_run
        @paper_capital_inr    = paper_capital_inr
      end

      def dry_run_capital_usd
        if @paper_capital_inr
          (@paper_capital_inr / @usd_to_inr_rate).round(2)
        else
          DEFAULT_DRY_RUN_CAPITAL_USD
        end
      end

      def available_usdt
        return dry_run_capital_usd if @dry_run

        # Delta Exchange India uses "USD" as the margin asset for USD-settled
        # perpetuals; try USDT first then fall back to USD.
        balance = DeltaExchange::Models::WalletBalance.find_by_asset("USDT") ||
                  DeltaExchange::Models::WalletBalance.find_by_asset("USD")
        balance&.available_balance.to_f || 0.0
      end

      def available_inr
        available_usdt * @usd_to_inr_rate
      end
    end
  end
end
