# frozen_string_literal: true

class PaperOrder < ApplicationRecord
  belongs_to :paper_wallet
  belongs_to :paper_product_snapshot
  belongs_to :paper_trading_signal
  has_many :paper_fills, dependent: :destroy

  validates :side, inclusion: { in: %w[buy sell long short] }
  validates :size, numericality: { only_integer: true, greater_than: 0 }
  validates :client_order_id, uniqueness: true
  validates :state, presence: true
end
