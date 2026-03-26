# app/services/trading/event_bus.rb
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
