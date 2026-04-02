# frozen_string_literal: true

class PaperTradingSignal < ApplicationRecord
  belongs_to :paper_wallet
  has_many :paper_orders, dependent: :restrict_with_exception

  STATUSES = %w[pending accepted routed rejected filled closed].freeze

  validates :product_id, :side, :entry_price, :stop_price, :max_loss_inr, :idempotency_key, presence: true
  validates :max_loss_inr, numericality: { greater_than: 0 }
  validates :idempotency_key, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :side, inclusion: { in: %w[buy sell long short] }

  def pending?
    status == "pending"
  end

  def rejected?
    status == "rejected"
  end

  def filled?
    status == "filled"
  end
end
