# frozen_string_literal: true

class GeneratedSignal < ApplicationRecord
  SOURCES = %w[mtf adaptive].freeze
  STATUSES = %w[generated executed rejected failed skipped_duplicate].freeze
  SIDES = %w[buy sell long short].freeze

  belongs_to :trading_session

  validates :symbol, presence: true
  validates :side, inclusion: { in: SIDES }
  validates :strategy, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
end
