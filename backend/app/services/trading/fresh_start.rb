# frozen_string_literal: true

module Trading
  # One-shot reset of trading execution state (DB + documented Redis/cache scope).
  # See README "Fresh start" and `bin/rails trading:fresh_start`.
  class FreshStart
    class AbortError < StandardError; end

    # Redis DB used by `Redis.current` (see config/initializers/redis.rb), typically /0.
    # Does not touch Solid Queue (PostgreSQL) or Rails cache Redis DB if different.
    REDIS_DB0_DOCUMENTED_KEYS = [
      "delta:positions:live",
      "delta:wallet:state",
      "delta:execution:incidents",
      "delta:strategy:state",
      "learning:ai_refinement:enqueue_lock",
      Trading::SessionResumer::BOOT_LOCK_KEY
    ].freeze

    REDIS_DB0_SCAN_PATTERNS = [
      "delta_bot_lock:*",
      "delta:order:*",
      "delta_bot:prices:*"
    ].freeze

    def self.call!(confirm:, stdout: $stdout)
      new(confirm: confirm, stdout: stdout).call!
    end

    def initialize(confirm:, stdout: $stdout)
      @confirm = confirm
      @stdout = stdout
    end

    def call!
      raise AbortError, "Aborting. Run with CONFIRM=YES." unless @confirm.to_s == "YES"

      counts = {}
      ApplicationRecord.transaction do
        counts[:portfolio_ledger_entries] = PortfolioLedgerEntry.delete_all
        counts[:fills] = Fill.delete_all
        detached = Order.where.not(position_id: nil).update_all(position_id: nil)
        counts[:orders_detached] = detached
        counts[:orders] = Order.delete_all
        counts[:trades] = Trade.delete_all
        counts[:generated_signals] = GeneratedSignal.delete_all
        counts[:positions] = Position.delete_all
        counts[:strategy_params] = StrategyParam.delete_all
      end

      flush_redis_db0!
      flush_rails_cache!

      print_summary(counts)
    end

    private

    def redis
      @redis ||= Redis.current
    end

    def flush_redis_db0!
      REDIS_DB0_DOCUMENTED_KEYS.each do |key|
        redis.del(key)
      rescue StandardError => e
        @stdout.puts "[fresh_start] Redis DEL #{key}: #{e.message}"
      end

      REDIS_DB0_SCAN_PATTERNS.each { |pattern| scan_delete!(pattern) }
    end

    def scan_delete!(pattern)
      redis.scan_each(match: pattern) { |key| redis.del(key) }
    rescue StandardError => e
      @stdout.puts "[fresh_start] Redis SCAN #{pattern}: #{e.message}"
    end

    def flush_rails_cache!
      Rails.cache.clear
    rescue NotImplementedError, StandardError => e
      @stdout.puts "[fresh_start] Rails.cache.clear skipped: #{e.message}"
    end

    def print_summary(counts)
      @stdout.puts <<~MSG
        Trading::FreshStart complete.

        Database rows deleted:
          portfolio_ledger_entries: #{counts[:portfolio_ledger_entries]}
          fills:                    #{counts[:fills]}
          orders (rows):            #{counts[:orders]} (position_id cleared on #{counts[:orders_detached]} rows first)
          trades:                   #{counts[:trades]}
          generated_signals:        #{counts[:generated_signals]}
          positions:                #{counts[:positions]}
          strategy_params:          #{counts[:strategy_params]}

        Redis (Redis.current / DB from REDIS_URL): removed documented keys + SCAN patterns:
          #{REDIS_DB0_DOCUMENTED_KEYS.join(", ")}
          patterns: #{REDIS_DB0_SCAN_PATTERNS.join(", ")}

        Rails.cache: clear (LTP/mark, adaptive:*, runtime_config:*, idempotency not on cache store — see Redis delta:order:*).
      MSG
    end
  end
end
