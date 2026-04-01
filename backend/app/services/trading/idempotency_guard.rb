# frozen_string_literal: true

module Trading
  class IdempotencyGuard
    KEY_TTL = 3600  # 1 hour

    # Normalizes strategy sides (long/short) to exchange order sides (buy/sell) for stable keys.
    def self.exchange_side(strategy_side)
      case strategy_side.to_s.downcase
      when "long", "buy" then "buy"
      when "short", "sell" then "sell"
      else strategy_side.to_s
      end
    end

    def self.key_for_signal(signal)
      key(
        symbol: signal.symbol,
        side: exchange_side(signal.side),
        timestamp: signal.candle_timestamp.to_i
      )
    end

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
