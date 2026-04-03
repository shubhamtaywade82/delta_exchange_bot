# frozen_string_literal: true

# Fill stores immutable exchange execution events and is the idempotency source of truth.
class Fill < ApplicationRecord
  belongs_to :order

  validates :exchange_fill_id, presence: true, uniqueness: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :price, numericality: { greater_than: 0 }, allow_nil: true
  validates :fee, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :filled_at, presence: true

  scope :chronological, -> { order(:filled_at, :exchange_fill_id) }

  # Signed contract quantity: buy adds, sell reduces (linear perp convention).
  def signed_quantity
    return 0.to_d if quantity.blank?

    q = quantity.to_d
    order.side.to_s == "sell" ? -q : q
  end
end
