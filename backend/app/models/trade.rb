class Trade < ApplicationRecord
  # Single round-trip for dashboard KPIs (replaces several SUM/COUNT queries).
  def self.dashboard_pnl_totals(as_of: Time.zone.now)
    day_cutoff = as_of - 24.hours
    week_cutoff = as_of - 7.days

    row = connection.select_one(
      sanitize_sql_array([<<-SQL.squish, day_cutoff, week_cutoff])
        SELECT
          COALESCE(SUM(pnl_usd), 0)::double precision AS total_realized,
          COUNT(*)::bigint AS trade_count,
          COUNT(*) FILTER (WHERE pnl_usd > 0)::bigint AS win_count,
          COALESCE(SUM(pnl_usd) FILTER (WHERE closed_at IS NOT NULL AND closed_at >= ?), 0)::double precision AS daily_pnl,
          COALESCE(SUM(pnl_usd) FILTER (WHERE closed_at IS NOT NULL AND closed_at >= ?), 0)::double precision AS weekly_pnl
        FROM trades
      SQL
    )

    {
      total_realized: row.fetch("total_realized").to_f,
      trade_count: row.fetch("trade_count").to_i,
      win_count: row.fetch("win_count").to_i,
      daily_pnl: row.fetch("daily_pnl").to_f,
      weekly_pnl: row.fetch("weekly_pnl").to_f
    }
  end
end
