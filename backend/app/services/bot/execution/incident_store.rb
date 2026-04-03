# frozen_string_literal: true

require "json"

module Bot
  module Execution
    class IncidentStore
      INCIDENTS_KEY = "delta:execution:incidents"
      MAX_INCIDENTS = 200

      def self.record!(kind:, category:, message:, symbol: nil, signal_id: nil, details: {})
        entry = {
          ts: Time.current.iso8601,
          kind: kind,
          category: category,
          message: message.to_s,
          symbol: symbol,
          signal_id: signal_id,
          details: details || {}
        }
        redis.lpush(INCIDENTS_KEY, entry.to_json)
        redis.ltrim(INCIDENTS_KEY, 0, MAX_INCIDENTS - 1)
        entry
      rescue StandardError
        nil
      end

      def self.latest
        payload = redis.lindex(INCIDENTS_KEY, 0)
        return nil if payload.nil?

        JSON.parse(payload)
      rescue StandardError
        nil
      end

      def self.recent(limit: 20)
        size = [limit.to_i, 1].max
        redis.lrange(INCIDENTS_KEY, 0, size - 1).filter_map do |payload|
          JSON.parse(payload)
        rescue StandardError
          nil
        end
      rescue StandardError
        []
      end

      def self.redis
        Redis.current
      rescue StandardError
        Redis.new
      end
      private_class_method :redis
    end
  end
end
