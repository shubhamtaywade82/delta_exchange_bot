class Api::DashboardController < ApplicationController
  def index
    render json: {
      open_positions: Position.where(status: "open").count,
      total_trades: Trade.count,
      total_pnl_usd: Trade.sum(:pnl_usd).to_f.round(2),
      total_pnl_inr: Trade.sum(:pnl_inr).to_f.round(0),
      win_rate: Trade.count > 0 ? (Trade.where("pnl_usd > 0").count.to_f / Trade.count * 100).round(1) : 0
    }
  end
end
