class Api::DashboardController < ApplicationController
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
      
      trade_count = Trade.count
      win_rate = trade_count > 0 ? (Trade.where("pnl_usd > 0").count.to_f / trade_count * 100).round(1) : 0

      # Equity Curve from Trade history
      equity_curve = (0..6).to_a.reverse.map do |days_ago|
        date = days_ago.days.ago.to_date
        Trade.where("closed_at::date = ?", date).sum(:pnl_usd).to_f.round(2)
      end

      render json: {
        positions: active_positions.map { |p| 
          mark = Rails.cache.read("ltp:#{p.symbol}")&.to_f || p.entry_price.to_f
          {
            symbol: p.symbol,
            side: p.side,
            size: p.size,
            entry_price: p.entry_price,
            mark_price: mark,
            unrealized_pnl: (p.size.to_f * (p.side == 'buy' ? 1 : -1) * (mark - p.entry_price.to_f)).round(2),
            leverage: p.leverage,
            status: p.status
          }
        },
        trades: Trade.order(closed_at: :desc).limit(50).map { |t| 
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
        wallet: wallet,
        stats: {
          total_pnl_usd: total_pnl_usd,
          total_pnl_inr: (total_pnl_usd * 85.0).round(0),
          total_equity_usd: (wallet["balance"].to_f + portfolio.total_pnl).round(2),
          total_equity_inr: ((wallet["balance"].to_f + portfolio.total_pnl) * 85.0).round(0),
          win_rate: win_rate,
          daily_pnl: daily_pnl,
          weekly_pnl: weekly_pnl,
          equity_curve: equity_curve
        },
        market: market
      }
    end
  end
