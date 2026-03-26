# frozen_string_literal: true

require "redis"

module Bot
  module Feed
    class PriceStore
      REDIS_KEY_PREFIX = "delta_bot:prices:"

      def initialize
        @redis = Redis.new
      end

      def update(symbol, price)
        @redis.set("#{REDIS_KEY_PREFIX}#{symbol}", price.to_f)
      end

      def get(symbol)
        val = @redis.get("#{REDIS_KEY_PREFIX}#{symbol}")
        val&.to_f
      end

      def all
        keys   = @redis.keys("#{REDIS_KEY_PREFIX}*")
        return {} if keys.empty?
        
        values = @redis.mget(*keys)
        keys.map { |k| k.sub(REDIS_KEY_PREFIX, "") }
            .zip(values.map(&:to_f))
            .to_h
      end
    end
  end
end
