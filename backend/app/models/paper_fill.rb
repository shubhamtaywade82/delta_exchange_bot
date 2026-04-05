# frozen_string_literal: true

class PaperFill < ApplicationRecord
  belongs_to :paper_order

  before_validation :assign_accounting_defaults

  validates :size, numericality: { only_integer: true, greater_than: 0 }
  validates :filled_qty, numericality: { only_integer: true, greater_than: 0 }
  validates :closed_qty, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :liquidity, inclusion: { in: %w[maker taker] }
  validates :price, :filled_at, presence: true

  private

  def assign_accounting_defaults
    self.filled_qty ||= size
    self.closed_qty ||= 0
    self.margin_inr_per_fill ||= 0
    self.liquidity ||= "taker"
  end
end
