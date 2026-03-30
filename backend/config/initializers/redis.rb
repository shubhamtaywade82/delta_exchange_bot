# frozen_string_literal: true

require "redis"

Redis.singleton_class.define_method(:current) do
  @current ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
end
