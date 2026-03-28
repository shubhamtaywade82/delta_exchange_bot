# frozen_string_literal: true

require "redis"

module Bot
  module Account
    class CapitalManager
      attr_reader :usd_to_inr_rate

      REDIS_KEY = "delta:wallet:state"

      def initialize(usd_to_inr_rate:, dry_run: false, simulated_capital_inr: 10_000.0)
        @usd_to_inr_rate        = usd_to_inr_rate
        @dry_run                = dry_run
        @simulated_capital_inr  = simulated_capital_inr
        @redis                  = Redis.new
      end

      def available_usdt(blocked_margin: 0.0, unrealized_pnl: 0.0)
        # Delta Exchange India uses "USD" as the margin asset for USD-settled
        # perpetuals; try USDT first then fall back to USD.
        balance = DeltaExchange::Models::WalletBalance.find_by_asset("USDT") ||
                  DeltaExchange::Models::WalletBalance.find_by_asset("USD")
        result = balance&.available_balance.to_f || 0.0
        
        # In dry_run mode use simulated capital + realized PnL - blocked margin + unrealized PnL
        if @dry_run && (result < 1.0 || ENV["FORCE_DRY_RUN_BALANCE"] == "true")
          realized_pnl = Trade.sum(:pnl_usd).to_f
          usd_cap = (@simulated_capital_inr / @usd_to_inr_rate).round(2)
          val = (usd_cap + realized_pnl - blocked_margin + unrealized_pnl).round(2)
          [val, 0.0].max # Don't show negative available balance in simulation
        else
          result
        end
      end

      def available_inr
        available_usdt * @usd_to_inr_rate
      end

      def persist_state(blocked_margin: 0.0, unrealized_pnl: 0.0)
        usd_available = available_usdt(blocked_margin: blocked_margin, unrealized_pnl: unrealized_pnl)
        
        data = {
          available_usd: usd_available,
          available_inr: (usd_available * @usd_to_inr_rate).round(0),
          capital_inr:   @simulated_capital_inr.round(0),
          paper_mode:    @dry_run,
          updated_at:    Time.current.iso8601,
          stale:         false
        }
        @redis.set(REDIS_KEY, data.to_json)
      rescue StandardError => e
        puts "Error persisting wallet state: #{e.message}"
      end
    end
  end
end
