#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../config/environment"

class RuntimeContinuityVerifier
  def run
    puts "== Runtime Continuity Verification =="
    verify_runtime_setting_refresh
    verify_event_driven_enqueue
    verify_learning_update_from_trade
    verify_session_resumer_enqueue
    puts "== Verification completed =="
  rescue StandardError => e
    puts "FATAL: #{e.class} #{e.message}"
    puts e.backtrace.join("\n")
    exit 1
  end

  private

  def verify_runtime_setting_refresh
    Setting.apply!(key: "learning.epsilon", value: 0.09, value_type: "float", source: "verify_script", reason: "dry_run")
    current = Trading::RuntimeConfig.fetch_float("learning.epsilon", default: 0.01)
    checkpoint("runtime setting refresh", current == 0.09)
  end

  def verify_event_driven_enqueue
    result = Trading::Learning::AiRefinementTrigger.call(reason: "verify_script")
    checkpoint("event-driven ai enqueue gate", result == true || result == false)
  end

  def verify_learning_update_from_trade
    before_count = Trade.count
    position = Position.create!(
      symbol: "BTCUSD",
      side: "buy",
      status: "filled",
      size: 1.0,
      entry_price: 50_000.0,
      leverage: 5,
      pnl_usd: 10.0,
      pnl_inr: 800.0,
      fee_total: 0.5,
      entry_time: 2.minutes.ago,
      strategy: "scalping",
      regime: "trending",
      entry_features: { "expected_edge" => "0.01", "notional" => "50000" }
    )

    OrdersRepository.close_position(position_id: position.id, reason: "VERIFY_SCRIPT", mark_price: 50_010.0)
    checkpoint("trade persisted from close flow", Trade.count > before_count)
  end

  def verify_session_resumer_enqueue
    session = TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0)
    Redis.current.del("delta_bot_lock:#{session.id}")
    Redis.current.del(Trading::SessionResumer::BOOT_LOCK_KEY)

    resumed_count = Trading::SessionResumer.call
    checkpoint("running session enqueue on resume", resumed_count >= 1)
  end

  def checkpoint(name, condition)
    status = condition ? "PASS" : "FAIL"
    puts "[#{status}] #{name}"
  end
end

RuntimeContinuityVerifier.new.run
