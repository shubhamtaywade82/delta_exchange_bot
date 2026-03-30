# frozen_string_literal: true

module Trading
  module Learning
    # Metrics keeps rolling reward stats per strategy/regime in cache.
    class Metrics
      # @param trade [Trade]
      # @return [Hash]
      def self.update(trade)
        key = key_for(trade.strategy, trade.regime)
        metric = Rails.cache.fetch(key, expires_in: 1.hour) { { n: 0, mean: 0.0 } }

        n = metric[:n] + 1
        reward = Reward.call(trade).to_f
        mean = metric[:mean] + ((reward - metric[:mean]) / n)

        updated = { n: n, mean: mean }
        Rails.cache.write(key, updated, expires_in: 1.hour)
        updated
      end

      def self.score(strategy, regime)
        metric = Rails.cache.read(key_for(strategy, regime))
        metric ? metric[:mean].to_f : 0.0
      end

      def self.sample_size(strategy, regime)
        metric = Rails.cache.read(key_for(strategy, regime))
        metric ? metric[:n].to_i : 0
      end

      def self.key_for(strategy, regime)
        "learning:metrics:#{strategy}:#{regime}"
      end
    end
  end
end
