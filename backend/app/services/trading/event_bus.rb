# frozen_string_literal: true

# In-process pub/sub for the trading process. Contract: at most one Trading::Runner (or equivalent)
# long-lived loop per OS process — subscribers are global class state and Runner#start calls reset!.
# Do not run multiple runners in one process without replacing this with an injectable bus.
module Trading
  class EventBus
    @subscribers = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new

    class << self
      def subscribe(event_type, &handler)
        @mutex.synchronize { @subscribers[event_type] << handler }
      end

      def publish(event_type, payload)
        handlers = @mutex.synchronize { @subscribers[event_type].dup }
        handlers.each do |handler|
          handler.call(payload)
        rescue => e
          Rails.logger.error("[EventBus] Handler error for #{event_type}: #{e.message}")
        end
      end

      def reset!
        @mutex.synchronize { @subscribers.clear }
      end
    end
  end
end
