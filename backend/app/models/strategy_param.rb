# frozen_string_literal: true

# StrategyParam stores bounded online-learning parameters per strategy+regime.
class StrategyParam < ApplicationRecord
  validates :strategy, presence: true
  validates :regime, presence: true
  validates :strategy, uniqueness: { scope: :regime }
end
