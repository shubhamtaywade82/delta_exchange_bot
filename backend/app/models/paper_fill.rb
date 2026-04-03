# frozen_string_literal: true

class PaperFill < ApplicationRecord
  belongs_to :paper_order

  validates :size, numericality: { only_integer: true, greater_than: 0 }
  validates :price, :filled_at, presence: true
end
