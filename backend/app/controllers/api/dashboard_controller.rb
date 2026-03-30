class Api::DashboardController < ApplicationController
  def index
    redis  = Redis.new
    prices = Bot::Feed::PriceStore.new.all
    config = Bot::Config.load
    
    # Live stats from Redis
    live_positions = JSON.parse(redis.get("delta:positions:live") || "{}")
    wallet         = JSON.parse(redis.get("delta:wallet:state") || "{}")
    unrealized     = live_positions["unrealized_pnl"]&.to_f || 0.0
    
    # Market data context
    market = config.symbol_names.map do |symbol|
      {
        symbol: symbol,
        price: prices[symbol] || 0.0,
        leverage: config.leverage_for(symbol)
      }
    end

    # PnL Metrics
    total_pnl_usd = (Trade.sum(:pnl_usd).to_f + unrealized).round(2)
    daily_pnl     = Trade.where("closed_at >= ?", 24.hours.ago).sum(:pnl_usd).to_f.round(2)
    weekly_pnl    = Trade.where("closed_at >= ?", 7.days.ago).sum(:pnl_usd).to_f.round(2)
    win_rate      = Trade.count > 0 ? (Trade.where("pnl_usd > 0").count.to_f / Trade.count * 100).round(1) : 0

    # Equity Curve
    equity_curve = (0..6).to_a.reverse.map do |days_ago|
      date = days_ago.days.ago.to_date
      Trade.where("closed_at::date = ?", date).sum(:pnl_usd).to_f.round(2)
    end

    render json: {
      positions: live_positions["positions"]&.values || [],
      trades:    Trade.order(closed_at: :desc).limit(50).map { |t| 
        { 
          symbol: t.symbol, 
          side: t.side, 
          entry_price: t.entry_price, 
          exit_price: t.exit_price, 
          pnl_usd: t.pnl_usd, 
          pnl_inr: (t.pnl_usd.to_f * 85.0).round(0), 
          timestamp: t.closed_at 
        } 
      },
      wallet:    wallet,
      stats: {
        total_pnl_usd: total_pnl_usd,
        total_pnl_inr: (total_pnl_usd * 85.0).round(0),
        total_equity_usd: (10000.0 / 85.0 + Trade.sum(:pnl_usd).to_f + unrealized).round(2),
        total_equity_inr: (10000.0 + (Trade.sum(:pnl_usd).to_f + unrealized) * 85.0).round(0),
        win_rate: win_rate,
        daily_pnl: daily_pnl,
        weekly_pnl: weekly_pnl,
        equity_curve: equity_curve
      },
      market: market
    }
  end
end
