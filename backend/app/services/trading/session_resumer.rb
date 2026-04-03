# frozen_string_literal: true

module Trading
  class SessionResumer
    BOOT_LOCK_KEY = "delta_bot_session_resumer:boot_lock"
    BOOT_LOCK_TTL_SECONDS = 30

    def self.call
      new.call
    end

    def call
      return 0 unless acquire_boot_lock

      resumed_count = 0
      TradingSession.where(status: "running").find_each do |session|
        next if lock_held_for_session?(session.id)

        DeltaTradingJob.perform_later(session.id)
        resumed_count += 1
      end
      resumed_count
    rescue StandardError => e
      Rails.logger.warn("[SessionResumer] skipped: #{e.class} #{e.message}")
      0
    end

    private

    def acquire_boot_lock
      Redis.current.set(BOOT_LOCK_KEY, Time.current.to_i, nx: true, ex: BOOT_LOCK_TTL_SECONDS)
    end

    def lock_held_for_session?(session_id)
      Redis.current.exists?("delta_bot_lock:#{session_id}")
    end
  end
end
