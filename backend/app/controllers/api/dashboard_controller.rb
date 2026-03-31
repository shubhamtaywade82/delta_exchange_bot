class Api::DashboardController < ApplicationController
  USD_INR_FOR_DISPLAY = 85.0

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

    render json: {
      positions: active_positions.map { |p| position_payload(p) },
      trades: Trade.order(closed_at: :desc).limit(50).map { |t|
        {
          symbol: t.symbol,
          side: t.side,
          entry_price: t.entry_price,
          exit_price: t.exit_price,
          pnl_usd: t.pnl_usd,
          pnl_inr: (t.pnl_usd.to_f * USD_INR_FOR_DISPLAY).round(0),
          timestamp: t.closed_at
        }
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

  def position_payload(position)
    mark = Rails.cache.read("ltp:#{position.symbol}")&.to_f || position.entry_price.to_f
    unrealized_usd = Trading::Risk::PositionRisk
      .call(position: position, mark_price: mark).unrealized_pnl.to_f.round(2)

    {
      symbol: position.symbol,
      side: position.side,
      size: position.size,
      entry_price: position.entry_price,
      mark_price: mark,
      unrealized_pnl: unrealized_usd,
      unrealized_pnl_inr: (unrealized_usd * USD_INR_FOR_DISPLAY).round(0),
      unrealized_pnl_pct: unrealized_pnl_pct(position, unrealized_usd),
      leverage: position.leverage,
      status: position.status
    }
  end

  # ROE% must use the same exposure basis as unrealized_usd.
  # `unrealized_usd` from Trading::Risk::PositionRisk currently does not apply
  # contract_value, so we intentionally keep the denominator aligned here.
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

    (lots * entry) / lev
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
