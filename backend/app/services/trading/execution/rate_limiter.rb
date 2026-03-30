# frozen_string_literal: true

module Trading
  module Execution
    # RateLimiter applies token-bucket throttling to outbound exchange calls.
    class RateLimiter
      MAX_TOKENS = ENV.fetch("EXECUTION_MAX_TOKENS", 50).to_i
      REFILL_RATE = ENV.fetch("EXECUTION_REFILL_RATE", 50).to_i

      def initialize
        @tokens = MAX_TOKENS
        @last_refill = Time.now
        @mutex = Mutex.new
      end

      def allow?
        @mutex.synchronize do
          refill!
          return false if @tokens <= 0

          @tokens -= 1
          true
        end
      end

      private

      def refill!
        now = Time.now
        delta = now - @last_refill
        refill_tokens = (delta * REFILL_RATE).to_i
        return if refill_tokens <= 0

        @tokens = [@tokens + refill_tokens, MAX_TOKENS].min
        @last_refill = now
      end
    end
  end
end
