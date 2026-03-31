class Api::DashboardController < ApplicationController
  USD_INR_FOR_DISPLAY = 85.0
  BROKER_TRADES_LIMIT_DEFAULT = 500
  BROKER_TRADES_LIMIT_MAX = 2000

  def index
    # Use the new production architecture sources of truth
    active_positions = Position.active.to_a
    portfolio = Trading::Risk::PortfolioSnapshot.current

    # For now, we still pull wallet from Redis if it's there, but default to calculated
    redis = Redis.new
    wallet_json = redis.get("delta:wallet:state")
    wallet = wallet_json ? JSON.parse(wallet_json) : { "balance" => 1000.0, "equity" => 1000.0 + portfolio.total_pnl }

    # Market data context from SymbolConfigs
    market = SymbolConfig.where(enabled: true).map do |config|
      {
        symbol: config.symbol,
        price: Rails.cache.read("ltp:#{config.symbol}")&.to_f || 0.0,
        leverage: config.leverage
      }
    end

    # PnL Metrics from database
    total_realized = Trade.sum(:pnl_usd).to_f
    total_pnl_usd = (total_realized + portfolio.total_pnl).round(2)
    daily_pnl = Trade.where("closed_at >= ?", 24.hours.ago).sum(:pnl_usd).to_f.round(2)
    weekly_pnl = Trade.where("closed_at >= ?", 7.days.ago).sum(:pnl_usd).to_f.round(2)
    execution_health = build_execution_health

    trade_count = Trade.count
    win_rate = trade_count > 0 ? (Trade.where("pnl_usd > 0").count.to_f / trade_count * 100).round(1) : 0

    # Equity Curve from Trade history
    equity_curve = (0..6).to_a.reverse.map do |days_ago|
      date = days_ago.days.ago.to_date
      Trade.where("closed_at::date = ?", date).sum(:pnl_usd).to_f.round(2)
    end

    trades_scope = broker_settled_trades_scope.where(closed_at: trades_day_range)
    trades_total = trades_scope.count
    trades_limit = trades_limit_param
    trade_rows = trades_scope.order(closed_at: :desc).limit(trades_limit)

    render json: {
      positions: active_positions.map { |p| position_payload(p) },
      trades: trade_rows.map { |t| trade_payload(t) },
      trades_meta: {
        total_count: trades_total,
        limit: trades_limit,
        day: trades_day_param.strftime("%Y-%m-%d")
      },
      wallet: wallet,
      stats: {
        total_pnl_usd: total_pnl_usd,
        total_pnl_inr: (total_pnl_usd * USD_INR_FOR_DISPLAY).round(0),
        total_equity_usd: (wallet["balance"].to_f + portfolio.total_pnl).round(2),
        total_equity_inr: ((wallet["balance"].to_f + portfolio.total_pnl) * USD_INR_FOR_DISPLAY).round(0),
        win_rate: win_rate,
        daily_pnl: daily_pnl,
        weekly_pnl: weekly_pnl,
        equity_curve: equity_curve
      },
      market: market,
      execution_health: execution_health
    }
  end

  private

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

    {
      symbol: position.symbol,
      side: position.side,
      size: position.size,
      entry_price: entry_price,
      mark_price: mark,
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
