# frozen_string_literal: true

namespace :trading do
  desc <<~DESC.squish
    Full trading fresh start: deletes trades, fills, orders, ledger entries, positions,
    generated_signals, strategy_params (online-learning rows). Clears documented Redis keys
    on Redis.current and Rails.cache. Requires CONFIRM=YES.
    Stop the bot and job workers before running. See README "Fresh start".
  DESC
  task fresh_start: :environment do
    Trading::FreshStart.call!(confirm: ENV["CONFIRM"])
  end

  desc <<~DESC.squish
    Delete all positions and generated_signals (DB).
    Nullifies order.position_id first so FK constraints stay valid.
    Clears Redis key delta:positions:live if present.
    Requires CONFIRM=YES (e.g. CONFIRM=YES bin/rails trading:reset_positions_and_signals).
  DESC
  task reset_positions_and_signals: :environment do
    unless ENV["CONFIRM"].to_s == "YES"
      abort "Aborting. Run with CONFIRM=YES to delete every position and generated signal."
    end

    n_orders = 0
    n_signals = 0
    n_positions = 0

    ApplicationRecord.transaction do
      n_orders = Order.where.not(position_id: nil).update_all(position_id: nil)
      n_signals = GeneratedSignal.delete_all
      n_positions = Position.delete_all
    end

    begin
      Redis.new.del("delta:positions:live")
    rescue StandardError => e
      warn "[trading:reset_positions_and_signals] Redis: #{e.message}"
    end

    puts <<~MSG
      Done.
        orders_detached: #{n_orders} (position_id set to NULL)
        generated_signals_deleted: #{n_signals}
        positions_deleted: #{n_positions}
        cleared Redis key delta:positions:live (if Redis was reachable)
    MSG
  end
end
