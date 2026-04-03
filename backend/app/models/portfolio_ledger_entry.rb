# frozen_string_literal: true

# One row per fill: idempotent realized PnL application to the portfolio wallet.
class PortfolioLedgerEntry < ApplicationRecord
  belongs_to :portfolio
  belongs_to :fill

  validates :fill_id, uniqueness: true
  validates :realized_pnl_delta, :balance_delta, presence: true
  validates :realized_pnl_delta, :balance_delta, numericality: true
end
