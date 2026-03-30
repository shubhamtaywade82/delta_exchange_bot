# frozen_string_literal: true

class DeltaTradingJob < ApplicationJob
  queue_as :trading

  # Discard retries — a long-running bot re-spawning on failure creates duplicate
  # instances. Any restart must be an explicit new session dispatch.
  discard_on StandardError

  LOCK_TTL = 86_400  # 24 hours

  def perform(session_id)
    return unless acquire_lock(session_id)

    runner = Trading::Runner.new(session_id: session_id)
    setup_signal_handlers(runner)
    runner.start
  rescue => e
    Rails.logger.error("[DeltaTradingJob] Session #{session_id} crashed: #{e.class} #{e.message}")
    mark_session_crashed(session_id)
    raise
  ensure
    release_lock(session_id)
  end

  private

  def acquire_lock(session_id)
    acquired = Redis.current.set("delta_bot_lock:#{session_id}", 1, nx: true, ex: LOCK_TTL)
    Rails.logger.warn("[DeltaTradingJob] Lock already held for session #{session_id} — aborting") unless acquired
    acquired
  end

  def release_lock(session_id)
    Redis.current.del("delta_bot_lock:#{session_id}")
  end

  def setup_signal_handlers(runner)
    Signal.trap("TERM") { runner.stop }
    Signal.trap("INT")  { runner.stop }
  end

  def mark_session_crashed(session_id)
    TradingSession.find(session_id).update!(status: "crashed")
  rescue => e
    Rails.logger.error("[DeltaTradingJob] Could not mark session #{session_id} as crashed: #{e.message}")
  end
end
