# frozen_string_literal: true

module Trading
  # Async path: preflight with Paper::CapitalAllocator, then ExecutionEngine (idempotent per signal id).
  class ProcessGeneratedSignalJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(signal_id)
      signal = GeneratedSignal.find_by(id: signal_id)
      return if signal.nil?

      guard_key = "process_generated_signal:#{signal_id}"
      return unless IdempotencyGuard.acquire(guard_key)

      unless signal.status == "generated"
        IdempotencyGuard.release(guard_key)
        return
      end

      session = signal.trading_session
      allocation = Paper::SignalPreflight.call(signal)
      unless allocation.valid?
        signal.update!(
          status: "rejected",
          error_message: "paper preflight: risk sizing yields zero contracts"
        )
        IdempotencyGuard.release(guard_key)
        return
      end

      ev = Events::SignalGenerated.new(
        symbol: signal.symbol,
        side: signal.side,
        entry_price: signal.entry_price.to_f,
        candle_timestamp: signal.candle_timestamp,
        strategy: signal.strategy,
        session_id: session.id,
        stop_price: signal.stop_price&.to_f
      )

      client = RunnerClient.build
      order = ExecutionEngine.execute(ev, session: session, client: client)
      if order
        signal.update!(status: "executed")
      else
        signal.update!(
          status: "skipped_duplicate",
          error_message: "idempotency: same symbol/side/candle_timestamp already executed"
        )
      end
    rescue Trading::RiskManager::RiskError => e
      signal&.update!(status: "rejected", error_message: e.message.to_s.truncate(500))
      IdempotencyGuard.release(guard_key)
    rescue StandardError => e
      signal&.update!(status: "failed", error_message: e.message.to_s.truncate(500))
      IdempotencyGuard.release(guard_key)
      raise
    end
  end
end
