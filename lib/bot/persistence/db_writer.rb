# frozen_string_literal: true

require "pg"

module Bot
  module Persistence
    # Writes position and trade records directly to the Rails PostgreSQL database
    # so the frontend dashboard reflects live bot activity.
    class DbWriter
      def initialize(database: ENV.fetch("BOT_DB_NAME", "backend_development"),
                     host:     ENV.fetch("BOT_DB_HOST", "localhost"),
                     port:     ENV.fetch("BOT_DB_PORT", "5432").to_i,
                     user:     ENV.fetch("BOT_DB_USER", ENV["USER"]),
                     password: ENV.fetch("BOT_DB_PASSWORD", nil))
        @conn = PG.connect(dbname: database, host: host, port: port, user: user, password: password)
      rescue PG::Error => e
        warn "[DbWriter] DB connect failed: #{e.message} — position writes disabled"
        @conn = nil
      end

      # Called after @position_tracker.open(...)
      def record_opened(symbol:, side:, lots:, entry_price:, leverage:,
                        contract_value:, trail_pct:)
        return unless @conn

        now = Time.now.utc
        @conn.exec_params(
          <<~SQL,
            INSERT INTO positions
              (symbol, side, status, size, entry_price, leverage,
               contract_value, trail_pct, entry_time, created_at, updated_at)
            VALUES ($1, $2, 'open', $3, $4, $5, $6, $7, $8, $8, $8)
          SQL
          [symbol, side.to_s, lots, entry_price, leverage,
           contract_value, trail_pct, now.iso8601]
        )
      rescue PG::Error => e
        warn "[DbWriter] record_opened failed for #{symbol}: #{e.message}"
      end

      # Called after @position_tracker.close(symbol)
      def record_closed(symbol:, side:, lots:, entry_price:, exit_price:,
                        pnl_usd:, pnl_inr:, duration_seconds:)
        return unless @conn

        now = Time.now.utc

        @conn.exec_params(
          <<~SQL,
            UPDATE positions
            SET status = 'closed', exit_price = $1, pnl_usd = $2,
                pnl_inr = $3, exit_time = $4, updated_at = $4
            WHERE symbol = $5 AND status = 'open'
          SQL
          [exit_price, pnl_usd, pnl_inr, now.iso8601, symbol]
        )

        @conn.exec_params(
          <<~SQL,
            INSERT INTO trades
              (symbol, side, entry_price, exit_price, size, pnl_usd, pnl_inr,
               duration_seconds, closed_at, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9, $9)
          SQL
          [symbol, side.to_s, entry_price, exit_price, lots,
           pnl_usd, pnl_inr, duration_seconds, now.iso8601]
        )
      rescue PG::UniqueViolation
        # Ignore duplicate trade records to ensure data integrity without crashing.
      rescue PG::Error => e
        warn "[DbWriter] record_closed failed for #{symbol}: #{e.message}"
      end

      def close
        @conn&.close
      end
    end
  end
end
