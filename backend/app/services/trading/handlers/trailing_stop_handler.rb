# frozen_string_literal: true

module Trading
  module Handlers
    class TrailingStopHandler
      # Skip stop-*hit* exits for this many seconds after open so a tight trail is not taken out by
      # the first ticks right after fill. Set TRAILING_STOP_GRACE_SECONDS=0 to disable.
      DEFAULT_GRACE_SECONDS = 8

      def initialize(tick, client:)
        @tick   = tick
        @client = client
      end

      def call
        position = PositionsRepository.open_for(@tick.symbol)
        return unless position && position.trail_pct.present?
        return if position.stop_price.blank? || position.stop_price.to_f <= 0

        # 1. Update Trailing Stop logic
        action = update_stop(position)

        # 2. Trigger Exit if stop hit
        if action == :exit
          Rails.logger.warn("[TrailingStopHandler] STOP HIT for #{position.symbol} at #{@tick.price}")
          notify_trailing_stop_telegram(position)
          EmergencyShutdown.force_exit_position(position, @client, reason: "TRAILING_STOP_EXIT")
        end
      end

      private

      def update_stop(pos)
        ltp       = @tick.price
        trail_pct = pos.trail_pct.to_f / 100.0
        peak      = pos.peak_price.to_f
        updated   = false

        if pos.side == "long"
          if ltp > peak
            pos.peak_price = ltp
            pos.stop_price = ltp * (1.0 - trail_pct)
            updated = true
          end
          return :exit if !trailing_grace_period_active?(pos) && ltp <= pos.stop_price.to_f
        else # short
          if ltp < peak
            pos.peak_price = ltp
            pos.stop_price = ltp * (1.0 + trail_pct)
            updated = true
          end
          return :exit if !trailing_grace_period_active?(pos) && ltp >= pos.stop_price.to_f
        end

        pos.save! if updated
        nil
      end

      def trailing_grace_period_active?(position)
        sec = grace_seconds
        return false if sec <= 0

        t0 = position.entry_time.presence || position.created_at
        return false if t0.blank?

        Time.current - t0.to_time < sec
      end

      def grace_seconds
        ENV.fetch("TRAILING_STOP_GRACE_SECONDS", DEFAULT_GRACE_SECONDS.to_s).to_f
      end

      def notify_trailing_stop_telegram(position)
        cache_key = "telegram:trailing_stop_hit:#{position.id}"
        written = Rails.cache.write(cache_key, 1, expires_in: 12.seconds, unless_exist: true)
        return unless written

        side_sym = position.side.to_s.downcase.in?(%w[long buy]) ? :long : :short
        Trading::TelegramNotifications.deliver do |n|
          n.notify_trailing_stop_triggered(
            symbol: position.symbol,
            side: side_sym,
            ltp: @tick.price.to_f,
            stop_price: position.stop_price.to_f
          )
        end
      end
    end
  end
end
