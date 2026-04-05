# frozen_string_literal: true

# Wallet source of truth for ledger-first accounting (balance, available, used margin).
class Portfolio < ApplicationRecord
  # Bot CLI / legacy execution paths that open positions outside Trading::ExecutionEngine.
  def self.resolve_for_legacy_bot_execution!
    first || create!(
      balance: BigDecimal("1000000"),
      available_balance: BigDecimal("1000000"),
      used_margin: 0
    )
  end

  has_many :trading_sessions, dependent: :restrict_with_exception
  has_many :orders, dependent: :restrict_with_exception
  has_many :positions, dependent: :restrict_with_exception
  has_many :portfolio_ledger_entries, dependent: :destroy

  validates :balance, :available_balance, :used_margin, presence: true
  validates :balance, :available_balance, :used_margin, numericality: true

  def equity
    balance.to_d + unrealized_pnl_total
  end

  def unrealized_pnl_total
    positions.active.sum(Arel.sql("COALESCE(unrealized_pnl_usd, 0)::decimal"))
  end

  # Idempotent: one ledger row per fill; realized PnL credits balance; then margin sync.
  def apply_fill_and_sync!(fill, delta_realized:)
    with_lock do
      reload
      return if portfolio_ledger_entries.exists?(fill_id: fill.id)

      fee = fill.fee.to_d
      pnl = delta_realized.to_d
      wallet_delta = pnl - fee

      if wallet_delta.zero? && pnl.zero? && fee.zero?
        sync_margin_from_positions!
        return
      end

      portfolio_ledger_entries.create!(
        fill: fill,
        realized_pnl_delta: pnl,
        balance_delta: wallet_delta
      )
      update!(balance: balance.to_d + wallet_delta)
      sync_margin_from_positions!
    end
  end

  # Recomputes used_margin from active positions and sets available = balance - used_margin.
  def sync_margin_from_positions!
    um = positions.active.sum(Arel.sql("COALESCE(margin, 0)::decimal"))
    avail = balance.to_d - um
    update!(used_margin: um, available_balance: avail)
  end
end
