# frozen_string_literal: true

module Trading
  module Learning
    # AiRefinementTrigger enqueues refinement at most once per cooldown window.
    class AiRefinementTrigger
      LOCK_KEY = "learning:ai_refinement:enqueue_lock"
      COOLDOWN_SECONDS = 120

      def self.call(reason:)
        return false if reason.to_s.strip.empty?

        return false unless acquire_lock

        Trading::Learning::AiRefinementJob.perform_later
        true
      rescue StandardError => e
        Rails.logger.warn("[AiRefinementTrigger] skipped: #{e.class} #{e.message}")
        false
      end

      def self.acquire_lock
        Redis.current.set(LOCK_KEY, Time.current.to_i, nx: true, ex: COOLDOWN_SECONDS)
      end
      private_class_method :acquire_lock
    end
  end
end
