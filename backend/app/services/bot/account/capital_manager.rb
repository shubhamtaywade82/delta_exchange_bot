# frozen_string_literal: true

require "redis"

module Bot
  module Account
    class CapitalManager
      attr_reader :usd_to_inr_rate

      REDIS_KEY = "delta:wallet:state"

      def initialize(usd_to_inr_rate:, dry_run: false, simulated_capital_inr: 20_000.0)
        @usd_to_inr_rate        = usd_to_inr_rate
        @dry_run                = dry_run
        @simulated_capital_inr  = simulated_capital_inr
        @redis                  = Redis.new
      end

      # Total Equity (Initial + Realized + Unrealized)
      def total_equity_usdt(unrealized_pnl: 0.0)
        if @dry_run
          realized      = Trade.all.sum(:pnl_usd).to_f
          initial_usd   = (@simulated_capital_inr / @usd_to_inr_rate).round(2)
          (initial_usd + realized + unrealized_pnl).round(2)
        else
          # Delta Exchange India uses "USD" as the margin asset
          balance = DeltaExchange::Models::WalletBalance.find_by_asset("USDT") ||
                    DeltaExchange::Models::WalletBalance.find_by_asset("USD")
          result = balance&.available_balance.to_f || 0.0
          # In live mode, balance + unrealized from API
          result + unrealized_pnl
        end
      end

      # Spendable = Equity - Blocked Margin
      def spendable_usdt(blocked_margin: 0.0, unrealized_pnl: 0.0)
        (total_equity_usdt(unrealized_pnl: unrealized_pnl) - blocked_margin).round(2)
      end

      def available_inr(unrealized_pnl: 0.0)
        total_equity_usdt(unrealized_pnl: unrealized_pnl) * @usd_to_inr_rate
      end

      # @return [Hash, nil] wallet fields for API / Redis; nil if Redis write fails
      def persist_state(blocked_margin: 0.0, unrealized_pnl: 0.0)
        data = wallet_payload(blocked_margin: blocked_margin, unrealized_pnl: unrealized_pnl)
        @redis.set(REDIS_KEY, data.to_json)
        data
      rescue StandardError => e
        puts "Error persisting wallet state: #{e.message}"
        nil
      end

      def wallet_payload(blocked_margin: 0.0, unrealized_pnl: 0.0)
        equity_usd    = total_equity_usdt(unrealized_pnl: unrealized_pnl)
        spendable_usd = spendable_usdt(blocked_margin: blocked_margin, unrealized_pnl: unrealized_pnl)
        blocked       = blocked_margin.to_f

        {
          "total_equity_usd" => equity_usd,
          "total_equity_inr" => (equity_usd * @usd_to_inr_rate).round(0),
          "available_usd" => spendable_usd,
          "available_inr" => (spendable_usd * @usd_to_inr_rate).round(0),
          "blocked_margin_usd" => blocked.round(2),
          "blocked_margin_inr" => (blocked * @usd_to_inr_rate).round(0),
          "capital_inr" => @simulated_capital_inr.round(0),
          "paper_mode" => @dry_run,
          "updated_at" => Time.current.iso8601,
          "stale" => false
        }
      end
    end
  end
end
