# frozen_string_literal: true

module Trading
  class IdempotencyGuard
    KEY_TTL = 3600  # 1 hour

    def self.key(symbol:, side:, timestamp:)
      "delta:order:#{symbol}:#{side}:#{timestamp}"
    end

    def self.acquire(key)
      Redis.current.set(key, 1, nx: true, ex: KEY_TTL)
    end

    def self.release(key)
      Redis.current.del(key)
    end
  end
end
