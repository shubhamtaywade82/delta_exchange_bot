# frozen_string_literal: true

require "redis"

# Logical Redis DB is the path segment: redis://host:6379/1 → database 1. Keep REDIS_URL aligned with
# config.cache_store in development (see environments/development.rb) so LTP/cache and app keys share one DB.
Redis.singleton_class.define_method(:current) do
  @current ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
end
