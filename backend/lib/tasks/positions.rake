# frozen_string_literal: true

module TradingTasks
  module Positions
    module_function

    def with_pg_connection_hint
      yield
    rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
      warn <<~MSG

        PostgreSQL refused a connection (#{e.class}: #{e.message.to_s.lines.first&.strip}).

        This is almost always too many concurrent clients: each Rails process holds a pool (see config/database.yml `pool`).
        Stop extra processes (other `rails s`, `bin/jobs`, `bin/bot`, consoles), or:

          DATABASE_POOL=2 bin/rails trading:verify_positions

        Or raise the server limit / terminate idle sessions (as superuser), e.g.:

          SELECT pg_terminate_backend(pid) FROM pg_stat_activity
          WHERE datname = current_database() AND pid <> pg_backend_pid() AND state = 'idle';

      MSG
      raise
    end
  end
end

namespace :trading do
  desc "Recalculate all active positions from ledger fills (PositionRecalculator)"
  task reconcile_positions: :environment do
    TradingTasks::Positions.with_pg_connection_hint do
      n = Trading::PositionReconciliation.recalculate_all_active!
      puts "Recalculated #{n} active positions."
    end
  end

  desc "Log discrepancies between stored margin/unrealized vs canonical formulas"
  task verify_positions: :environment do
    TradingTasks::Positions.with_pg_connection_hint do
      Trading::PositionReconciliation.log_verify_active!
      issues = Trading::PositionReconciliation.verify_active_positions
      puts issues.empty? ? "OK — no mismatches beyond tolerance." : "#{issues.size} mismatch(es) logged."
    end
  end

  desc "Mark all active positions for the next ReconciliationJob (dirty flag)"
  task mark_positions_dirty: :environment do
    TradingTasks::Positions.with_pg_connection_hint do
      n = Trading::PositionReconciliation.mark_all_active_dirty!
      puts "Marked #{n} positions."
    end
  end

  desc "Compare entry / first fill vs 1m candle close at first fill time (uses Delta REST; see EntryOneMinuteSanity)"
  task verify_entry_1m: :environment do
    TradingTasks::Positions.with_pg_connection_hint do
      tol = ENV["ENTRY_1M_TOLERANCE_PCT"]&.to_f
      tol = 0.25 if tol.nil? || tol <= 0
      rows = Trading::Positions::EntryOneMinuteSanity.call(tolerance_pct: tol)
      if rows.empty?
        puts "No positions (open or closed) with entry and fills to check."
      else
        rows.each do |r|
          status = r.ok ? "OK" : "CHECK"
          lines = [
            "[#{status}] id=#{r.position_id} #{r.symbol} #{r.status}",
            "  entry(VWAP)=#{r.entry_price} first_fill=#{r.first_fill_price} @ #{r.first_fill_at} (#{r.fill_count} fills)",
            "  1m_close=#{r.candle_close.inspect} bar_open_ts=#{r.candle_open_ts.inspect}",
            "  |entry-close|%=#{r.diff_entry_vs_close_pct.inspect} |first-close|%=#{r.diff_first_fill_vs_close_pct.inspect}"
          ]
          lines << "  note: #{r.note}" if r.note.present?
          puts lines.join("\n")
        end

        bad = rows.reject(&:ok)
        puts bad.empty? ? "\nAll rows within #{tol}% (or informational only)." : "\n#{bad.size} row(s) flagged — review notes and tolerance."
      end
    end
  end
end
