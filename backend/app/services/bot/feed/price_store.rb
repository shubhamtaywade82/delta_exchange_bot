# frozen_string_literal: true

require "redis"

module Bot
  module Feed
    class PriceStore
      REDIS_KEY_PREFIX = "delta_bot:prices:"

      def initialize
        @redis = Redis.current
      end

      def update(symbol, price)
        @redis.set("#{REDIS_KEY_PREFIX}#{symbol}", price.to_f)
      end

      def get(symbol)
        val = @redis.get("#{REDIS_KEY_PREFIX}#{symbol}")
        val&.to_f
      end

      def all
        data = {}
        @redis.scan_each(match: "#{REDIS_KEY_PREFIX}*") do |key|
          symbol = key.sub(REDIS_KEY_PREFIX, "")
          data[symbol] = @redis.get(key).to_f
        end
        data
      end
    end
  end
end
