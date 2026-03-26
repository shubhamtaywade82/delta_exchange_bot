# frozen_string_literal: true

require "redis"

module Bot
  module Account
    class CapitalManager
      attr_reader :usd_to_inr_rate

      DRY_RUN_SIMULATED_CAPITAL_USD = 10_000.0

      REDIS_KEY = "delta:wallet:state"

      def initialize(usd_to_inr_rate:, dry_run: false)
        @usd_to_inr_rate = usd_to_inr_rate
        @dry_run         = dry_run
        @redis           = Redis.new
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

      def persist_state
        data = {
          available_usd: available_usdt.round(2),
          available_inr: available_inr.round(0),
          capital_inr: (available_usdt * @usd_to_inr_rate).round(0), # Simplified for now
          paper_mode: @dry_run,
          updated_at: Time.current.iso8601,
          stale: false
        }
        @redis.set(REDIS_KEY, data.to_json)
      rescue StandardError => e
        puts "Error persisting wallet state: #{e.message}"
      end
    end
  end
end
