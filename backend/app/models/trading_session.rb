# app/models/trading_session.rb
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
