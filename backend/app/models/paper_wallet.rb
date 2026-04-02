# frozen_string_literal: true

# Paper wallet amounts (+PaperProductSnapshot+ prices) are USD, aligned with Delta settlement;
# INR display uses +Finance::UsdInrRate+ / +risk.usd_to_inr_rate+ (see +Trading::PaperWalletPublisher+).
class PaperWallet < ApplicationRecord
  has_many :paper_trading_signals, dependent: :restrict_with_exception
  has_many :paper_orders, dependent: :restrict_with_exception
  has_many :paper_positions, dependent: :destroy
  has_many :paper_wallet_ledger_entries, dependent: :destroy

  validates :name, presence: true
  validates :cash_balance, :realized_pnl, :unrealized_pnl, :equity, :reserved_margin, presence: true

  def available_capital
    equity.to_d - reserved_margin.to_d
  end

  # Initial cash + closed-trade PnL only (excludes unrealized). Used for risk % sizing.
  def risk_sizing_equity_usd
    cash_balance.to_d + realized_pnl.to_d
  end

  # Sum of initial margin for each open paper position (matches PaperTrading::PositionManager margin math).
  def margin_reserved_from_open_positions
    paper_positions.reduce(0.to_d) do |sum, pos|
      lev = [ pos.leverage.to_i, 1 ].max.to_d
      sum + (pos.avg_entry_price.to_d * pos.net_quantity * pos.risk_unit_per_contract.to_d) / lev
    end
  end

  # ltp_map: { product_id(Integer) => BigDecimal }
  def refresh_snapshot!(ltp_map: {})
    with_lock do
      unrealized = paper_positions.includes(:paper_product_snapshot).reduce(0.to_d) do |sum, pos|
        pid = pos.paper_product_snapshot.product_id
        ltp = ltp_map[pid]&.to_d || pos.paper_product_snapshot.live_price&.to_d
        next sum unless ltp&.positive?

        sum + pos.unrealized_pnl(ltp)
      end

      reserved = margin_reserved_from_open_positions

      update!(
        unrealized_pnl: unrealized,
        reserved_margin: reserved,
        equity: cash_balance.to_d + realized_pnl.to_d + unrealized
      )
    end
  end
end
