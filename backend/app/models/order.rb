# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :trading_session

  STATUSES = %w[pending open partially_filled filled cancelled rejected].freeze
  SIDES    = %w[buy sell].freeze

  validates :symbol, presence: true
  validates :side, inclusion: { in: SIDES }
  validates :size, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: true

  def filled?
    status == "filled"
  end

  def open?
    status.in?(%w[open partially_filled])
  end

  def terminal?
    status.in?(%w[filled cancelled rejected])
  end
end
