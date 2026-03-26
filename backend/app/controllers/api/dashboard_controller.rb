class Api::DashboardController < ApplicationController
  def index
    redis  = Redis.new
    prices = Bot::Feed::PriceStore.new.all
    config = Bot::Config.load
    
    # Real Daily/Weekly PnL
    daily_pnl = Trade.where("closed_at >= ?", 24.hours.ago).sum(:pnl_usd).to_f.round(2)
    weekly_pnl = Trade.where("closed_at >= ?", 7.days.ago).sum(:pnl_usd).to_f.round(2)

    # Real Equity Curve (Last 7 Days)
    equity_curve = (0..6).to_a.reverse.map do |days_ago|
      date = days_ago.days.ago.to_date
      Trade.where("closed_at::date = ?", date).sum(:pnl_usd).to_f.round(2)
    end

    # Build market data for all configured symbols
    market = config.symbol_names.map do |symbol|
      {
        symbol: symbol,
        price: prices[symbol] || 0.0,
        leverage: config.leverage_for(symbol)
      }
    end

    live_positions = JSON.parse(redis.get("delta:positions:live") || "{}")
    unrealized     = live_positions["unrealized_pnl"]&.to_f || 0.0
    
    total_pnl_usd  = (Trade.sum(:pnl_usd).to_f + unrealized).round(2)
    win_rate       = Trade.count > 0 ? (Trade.where("pnl_usd > 0").count.to_f / Trade.count * 100).round(1) : 0

    render json: {
      open_positions: (live_positions["positions"] || {}).size,
      total_trades: Trade.count,
      total_pnl_usd: total_pnl_usd,
      total_pnl_inr: (total_pnl_usd * 85.0).round(0),
      win_rate: win_rate,
      daily_pnl: daily_pnl,
      weekly_pnl: weekly_pnl,
      equity_curve: equity_curve,
      market: market
    }
  end
end
