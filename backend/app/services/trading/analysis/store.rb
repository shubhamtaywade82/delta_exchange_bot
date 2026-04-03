# frozen_string_literal: true

module Trading
  module Analysis
    module Store
      REDIS_KEY = "delta:analysis:dashboard"

      module_function

      def write(payload)
        Redis.current.set(REDIS_KEY, JSON.generate(payload))
      end

      def read
        raw = Redis.current.get(REDIS_KEY)
        return empty_payload if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError, Redis::BaseError => e
        Rails.logger.warn("[Analysis::Store] read failed: #{e.message}")
        empty_payload
      end

      def empty_payload
        {
          "updated_at" => nil,
          "symbols" => [],
          "meta" => { "source" => "none", "error" => nil }
        }
      end
    end
  end
end
