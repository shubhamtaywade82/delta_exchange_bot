# frozen_string_literal: true

class PaperProductSnapshot < ApplicationRecord
  has_many :paper_orders, dependent: :restrict_with_exception
  has_many :paper_positions, dependent: :restrict_with_exception

  validates :product_id, :symbol, :contract_value, :tick_size, :risk_unit_per_contract, presence: true
  validates :product_id, uniqueness: true
  validates :symbol, uniqueness: true

  def live_price
    mark_price&.to_d&.positive? ? mark_price.to_d : close_price&.to_d
  end
end
