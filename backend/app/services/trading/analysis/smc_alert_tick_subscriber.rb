# frozen_string_literal: true

module Trading
  module Analysis
    # Invoked from +Trading::Runner+ on each +tick_received+ (same process as WebSocket LTP updates).
    class SmcAlertTickSubscriber
      class << self
        def call(tick)
          return unless tick.respond_to?(:symbol)

          SmcAlertEvaluator.call(symbol: tick.symbol)
        rescue StandardError => e
          HotPathErrorPolicy.log_swallowed_error(
            component: "SmcAlertTickSubscriber",
            operation: "call",
            error:     e,
            log_level: :warn,
            symbol:    tick&.symbol
          )
        end
      end
    end
  end
end
