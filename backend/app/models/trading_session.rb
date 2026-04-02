# app/models/trading_session.rb
# +capital+ (USD) seeds the portfolio and remains session metadata. Live risk sizing and +RiskManager+
# gates use +portfolio.balance+ (initial deposit plus realized PnL from fills) when positive; otherwise
# +capital+ is a fallback. All trading math stays in USD; INR is for display only (+Finance::UsdInrRate+).
class TradingSession < ApplicationRecord
  belongs_to :portfolio
  has_many :generated_signals, dependent: :delete_all

  STATUSES = %w[pending running stopped crashed].freeze

  validates :strategy, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_status
  # Must run in before_validation (not before_save) so belongs_to :portfolio passes.
  # Include every save, not only :create — otherwise find_or_initialize_by + update! leaves legacy nil portfolio_id.
  before_validation :ensure_portfolio

  def running?
    status == "running"
  end

  private

  def set_default_status
    self.status ||= "pending"
  end

  def ensure_portfolio
    return if portfolio_id.present?

    initial = capital&.to_d&.positive? ? capital.to_d : BigDecimal("20000")
    self.portfolio = Portfolio.create!(
      balance: initial,
      available_balance: initial,
      used_margin: 0
    )
  end
end
