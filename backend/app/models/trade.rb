class Trade < ApplicationRecord
  EFFECTIVE_PNL_ZERO_EPS = BigDecimal("1e-12")

  belongs_to :portfolio, optional: true
  belongs_to :position, optional: true

  # PnL for KPIs and dashboard when +pnl_usd+ was not backfilled (matches list inference in Snapshot).
  def effective_pnl_usd
    raw = pnl_usd.to_d
    return raw if raw.abs >= EFFECTIVE_PNL_ZERO_EPS
    return raw if entry_price.blank? || exit_price.blank? || size.blank?

    pseudo = Position.new(
      symbol: symbol,
      side: side,
      size: size,
      entry_price: entry_price,
      contract_value: nil
    )
    Trading::Risk::PositionRisk.call(position: pseudo, mark_price: exit_price).unrealized_pnl.to_d
  rescue StandardError
    raw
  end

  # Distinct calendar days (app TZ / DB date cast) with at least one broker-settled row — for trade history picker.
  def self.broker_settled_calendar_days
    where.not(symbol: [nil, ""])
      .where.not(closed_at: nil)
      .group(Arel.sql("closed_at::date"))
      .order(Arel.sql("closed_at::date DESC"))
      .pluck(Arel.sql("closed_at::date"))
  end

  def self.sum_effective_pnl_usd(relation)
    total = 0.to_d
    relation.find_each { |t| total += t.effective_pnl_usd }
    total.to_f
  end

  # Dashboard KPIs using +effective_pnl_usd+ so totals match the trade list when +pnl_usd+ was stored as 0.
  def self.dashboard_pnl_totals(as_of: Time.zone.now)
    day_cutoff = as_of - 24.hours
    week_cutoff = as_of - 7.days

    total_realized = 0.to_d
    daily_pnl = 0.to_d
    weekly_pnl = 0.to_d
    trade_count = 0
    win_count = 0

    unscoped.find_each do |t|
      pnl = t.effective_pnl_usd
      total_realized += pnl
      trade_count += 1
      win_count += 1 if pnl.positive?
      daily_pnl += pnl if t.closed_at.present? && t.closed_at >= day_cutoff
      weekly_pnl += pnl if t.closed_at.present? && t.closed_at >= week_cutoff
    end

    {
      total_realized: total_realized.to_f,
      trade_count: trade_count,
      win_count: win_count,
      daily_pnl: daily_pnl.to_f,
      weekly_pnl: weekly_pnl.to_f
    }
  end

  # Same KPI shape as +dashboard_pnl_totals+ but restricted to a relation (e.g. current paper session).
  def self.dashboard_pnl_totals_for_scope(relation, as_of: Time.zone.now)
    day_cutoff = as_of - 24.hours
    week_cutoff = as_of - 7.days

    total_realized = 0.to_d
    daily_pnl = 0.to_d
    weekly_pnl = 0.to_d
    trade_count = 0
    win_count = 0

    relation.find_each do |t|
      pnl = t.effective_pnl_usd
      total_realized += pnl
      trade_count += 1
      win_count += 1 if pnl.positive?
      daily_pnl += pnl if t.closed_at.present? && t.closed_at >= day_cutoff
      weekly_pnl += pnl if t.closed_at.present? && t.closed_at >= week_cutoff
    end

    {
      total_realized: total_realized.to_f,
      trade_count: trade_count,
      win_count: win_count,
      daily_pnl: daily_pnl.to_f,
      weekly_pnl: weekly_pnl.to_f
    }
  end
end
