class Api::DashboardController < ApplicationController
  USD_INR_FOR_DISPLAY = 85.0
  BROKER_TRADES_LIMIT_DEFAULT = 500
  BROKER_TRADES_LIMIT_MAX = 2000

  def index
    # All non-closed position rows (open as of today in-app), including legacy `open` status.
    active_positions = Position.active.order(:symbol).to_a
    portfolio = Trading::Risk::PortfolioSnapshot.from_positions(active_positions)

    # Paper: recompute on every dashboard read so spendable/blocked stay aligned with DB (Redis was fill-only).
    wallet = load_wallet_for_dashboard(portfolio: portfolio, positions: active_positions)
    stats_equity_usd = stats_total_equity_usd(wallet, portfolio)

    # Market data context from SymbolConfigs
    market = SymbolConfig.where(enabled: true).map do |config|
      {
        symbol: config.symbol,
        price: Rails.cache.read("ltp:#{config.symbol}")&.to_f || 0.0,
        leverage: config.leverage
      }
    end

    trade_totals = Trade.dashboard_pnl_totals
    total_pnl_usd = (trade_totals[:total_realized] + portfolio.total_pnl).round(2)
    daily_pnl = trade_totals[:daily_pnl].round(2)
    weekly_pnl = trade_totals[:weekly_pnl].round(2)
    execution_health = build_execution_health

    trade_count = trade_totals[:trade_count]
    win_rate = trade_count.positive? ? (trade_totals[:win_count].to_f / trade_count * 100).round(1) : 0

    equity_curve = equity_curve_from_trades

    trades_scope = broker_settled_trades_scope.where(closed_at: trades_day_range)
    trades_total = trades_scope.count
    trades_limit = trades_limit_param
    trade_rows = trades_scope.order(closed_at: :desc).limit(trades_limit)

    trade_calendar_days = Trade.broker_settled_calendar_days.map { |d| format_trade_calendar_day(d) }
    signal_activity = build_signal_activity

    render json: {
      positions: active_positions.map { |p| position_payload(p) },
      positions_meta: {
        as_of_date: calendar_day_param,
        count: active_positions.size
      },
      trades: trade_rows.map { |t| trade_payload(t) },
      trades_calendar_days: trade_calendar_days,
      trades_meta: {
        total_count: trades_total,
        limit: trades_limit,
        day: trades_day_param.strftime("%Y-%m-%d")
      },
      wallet: wallet,
      stats: {
        total_pnl_usd: total_pnl_usd,
        total_pnl_inr: (total_pnl_usd * USD_INR_FOR_DISPLAY).round(0),
        total_equity_usd: stats_equity_usd,
        total_equity_inr: (stats_equity_usd * USD_INR_FOR_DISPLAY).round(0),
        win_rate: win_rate,
        daily_pnl: daily_pnl,
        weekly_pnl: weekly_pnl,
        equity_curve: equity_curve
      },
      market: market,
      execution_health: execution_health,
      signal_activity: signal_activity
    }
  end

  private

  def format_trade_calendar_day(value)
    return value.strftime("%Y-%m-%d") if value.respond_to?(:strftime)

    value.to_s
  end

  def load_wallet_for_dashboard(portfolio:, positions:)
    wallet =
      if Trading::PaperTrading.enabled?
        Trading::PaperWalletPublisher.wallet_snapshot!(positions: positions)
      else
        redis_wallet_hash
      end
    wallet.presence || default_wallet_hash(portfolio, positions: positions)
  end

  # One query for the last seven calendar days of realized PnL (same ordering as legacy per-day SUMs).
  def equity_curve_from_trades
    curve_dates = (0..6).to_a.reverse.map { |days_ago| days_ago.days.ago.in_time_zone.to_date }
    rows = Trade.where.not(closed_at: nil).where("closed_at::date IN (?)", curve_dates).pluck(:closed_at, :pnl_usd)
    by_date = Hash.new(0.0)
    rows.each { |closed_at, pnl| by_date[closed_at.in_time_zone.to_date] += pnl.to_f }
    curve_dates.map { |date| by_date[date].round(2) }
  end

  def redis_wallet_hash
    raw = Redis.new.get("delta:wallet:state")
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  # +positions+ reserved for paper/unrealized consistency if the Redis snapshot is missing (unused today).
  def default_wallet_hash(portfolio, positions: nil)
    {
      "balance" => 1000.0,
      "equity" => 1000.0 + portfolio.total_pnl.to_f
    }
  end

  def stats_total_equity_usd(wallet, portfolio)
    if wallet["total_equity_usd"].present?
      wallet["total_equity_usd"].to_f.round(2)
    else
      (wallet["balance"].to_f + portfolio.total_pnl.to_f).round(2)
    end
  end

  # Browser local calendar day (YYYY-MM-DD) for labels; avoids server UTC vs local mismatch.
  def calendar_day_param
    raw = params[:calendar_day].to_s.strip
    return Time.zone.today.strftime("%Y-%m-%d") if raw.blank?

    Date.iso8601(raw).strftime("%Y-%m-%d")
  rescue ArgumentError
    Time.zone.today.strftime("%Y-%m-%d")
  end

  # Lists only exchange/bot closed trades (symbol present). Omits learning-only rows
  # (e.g. CreditAssigner) that have no symbol and produced bogus UNKNOWN lines in the UI.
  def broker_settled_trades_scope
    Trade.where.not(symbol: [nil, ""])
         .where.not(closed_at: nil)
  end

  # Trade list is always scoped to one calendar day. When the client omits the param,
  # default to the current day in Time.zone so history opens on "today".
  def trades_day_param
    raw = params[:trades_day].to_s.strip
    return Time.zone.today if raw.blank?

    Date.iso8601(raw)
  rescue ArgumentError
    Time.zone.today
  end

  def trades_day_range
    trades_day_param.in_time_zone.all_day
  end

  def trades_limit_param
    limit = params.fetch(:trades_limit, BROKER_TRADES_LIMIT_DEFAULT).to_i
    limit = BROKER_TRADES_LIMIT_DEFAULT if limit <= 0
    [limit, BROKER_TRADES_LIMIT_MAX].min
  end

  def trade_payload(trade)
    {
      symbol: trade.symbol,
      side: trade.side,
      entry_price: trade.entry_price,
      exit_price: trade.exit_price,
      pnl_usd: trade.pnl_usd,
      pnl_inr: (trade.pnl_usd.to_f * USD_INR_FOR_DISPLAY).round(0),
      timestamp: trade.closed_at
    }
  end

  def position_payload(position)
    # Always show persisted `entry_price` / LTP — do not rewrite entry from OHLCV.
    # One active Position row per symbol is typically updated on new fills; `entry_time`
    # often stays at the first open, so candle-based "correction" skewed displayed entry.
    entry_price = position.entry_price.to_f
    mark = Rails.cache.read("ltp:#{position.symbol}")&.to_f || entry_price
    unrealized_usd = unrealized_pnl_usd(position: position, mark: mark, entry: entry_price).round(2)

    opened_at = position.entry_time || position.created_at

    {
      symbol: position.symbol,
      side: position.side,
      size: position.size,
      entry_price: entry_price,
      mark_price: mark,
      opened_at: opened_at&.iso8601,
      unrealized_pnl: unrealized_usd,
      unrealized_pnl_inr: (unrealized_usd * USD_INR_FOR_DISPLAY).round(0),
      unrealized_pnl_pct: unrealized_pnl_pct(position, unrealized_usd),
      leverage: position.leverage,
      status: position.status
    }
  end

  # ROE% must use the same exposure basis as unrealized_usd (contracts × lot_size / contract_value).
  def unrealized_pnl_pct(position, unrealized_usd)
    return 0.0 if unrealized_usd.zero?

    denominator = initial_margin_usd(position)
    return 0.0 if denominator.abs < 1e-12

    ((unrealized_usd / denominator) * 100).round(2)
  end

  def initial_margin_usd(position)
    lev = position.leverage.to_f
    return 0.0 if lev <= 0

    lots = position.size.to_f
    entry = position.entry_price.to_f
    return 0.0 if lots <= 0 || entry <= 0

    lot = Trading::Risk::PositionLotSize.multiplier_for(position).to_f
    (lots * lot * entry) / lev
  end

  def unrealized_pnl_usd(position:, mark:, entry:)
    direction = position.side.in?(%w[sell short]) ? -1.0 : 1.0
    lots = position.size.to_f.abs
    lot = Trading::Risk::PositionLotSize.multiplier_for(position).to_f
    qty = lots * lot
    (mark.to_f - entry.to_f) * qty * direction
  end

  def build_signal_activity
    {
      last_signal: signal_activity_payload(GeneratedSignal.order(created_at: :desc).first),
      last_rejection: signal_activity_payload(
        GeneratedSignal.where(status: %w[rejected failed]).order(created_at: :desc).first
      )
    }
  end

  def signal_activity_payload(record)
    return nil unless record

    {
      id: record.id,
      symbol: record.symbol,
      side: record.side,
      status: record.status,
      strategy: record.strategy,
      source: record.source,
      entry_price: record.entry_price.to_f,
      candle_timestamp: record.candle_timestamp,
      error_message: record.error_message,
      created_at: record.created_at.iso8601(3)
    }
  end

  def build_execution_health
    latest = Bot::Execution::IncidentStore.latest
    return { healthy: true, last_order_error: nil, last_broker_error_code: nil, category: nil, recent_incidents: [] } if latest.nil?

    {
      healthy: false,
      category: latest["category"],
      last_order_error: latest["message"],
      last_broker_error_code: latest.dig("details", "broker_code"),
      recent_incidents: Bot::Execution::IncidentStore.recent(limit: 10)
    }
  end
end
