# frozen_string_literal: true

module Trading
  module Handlers
    class TrailingStopHandler
      def initialize(tick, client:)
        @tick   = tick
        @client = client
      end

      def call
        position = PositionsRepository.open_for(@tick.symbol)
        return unless position && position.trail_pct.present?

        # 1. Update Trailing Stop logic
        action = update_stop(position)

        # 2. Trigger Exit if stop hit
        if action == :exit
          Rails.logger.warn("[TrailingStopHandler] STOP HIT for #{position.symbol} at #{@tick.price}")
          EmergencyShutdown.force_exit_position(position, @client, reason: "TRAILING_STOP_EXIT")
        end
      end

      private

      def update_stop(pos)
        ltp       = @tick.price
        trail_pct = pos.trail_pct.to_f / 100.0
        peak      = pos.peak_price.to_f
        stop      = pos.stop_price.to_f
        updated   = false

        if pos.side == "long"
          if ltp > peak
            pos.peak_price = ltp
            pos.stop_price = ltp * (1.0 - trail_pct)
            updated = true
          end
          return :exit if ltp <= pos.stop_price
        else # short
          if ltp < peak
            pos.peak_price = ltp
            pos.stop_price = ltp * (1.0 + trail_pct)
            updated = true
          end
          return :exit if ltp >= pos.stop_price
        end

        pos.save! if updated
        nil
      end
    end
  end
end
