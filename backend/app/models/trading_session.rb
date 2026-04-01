# app/models/trading_session.rb
# +capital+ is interpreted as USD equity for risk sizing: OrderBuilder multiplies by Finance::UsdInrRate
# then Finance::PositionSizer divides back to USD. +RiskManager+ daily loss compares +Trade.pnl_usd+ to
# a cap derived from the same field — keep capital and pnl in USD for consistent gates.
class TradingSession < ApplicationRecord
  has_many :generated_signals, dependent: :delete_all

  STATUSES = %w[pending running stopped crashed].freeze

  validates :strategy, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_status

  def running?
    status == "running"
  end

  private

  def set_default_status
    self.status ||= "pending"
  end
end
