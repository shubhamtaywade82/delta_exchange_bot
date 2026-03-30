# frozen_string_literal: true

# Position tracks lifecycle of a single directional exposure on an instrument.
#
# State progression:
# INIT -> ENTRY_PENDING -> PARTIALLY_FILLED -> FILLED -> EXIT_PENDING -> CLOSED
class Position < ApplicationRecord
  has_many :orders, dependent: :nullify

  STATES = %w[init entry_pending partially_filled filled exit_pending closed liquidated rejected].freeze
  SIDES = %w[buy sell long short].freeze

  validates :symbol, presence: true
  validates :status, inclusion: { in: STATES }
  validates :side, inclusion: { in: SIDES }, allow_nil: true
  validates :size, numericality: { greater_than: 0 }, allow_nil: true

  scope :active, -> { where(status: %w[entry_pending partially_filled filled exit_pending]) }

  TRANSITIONS = {
    "init" => %w[entry_pending rejected],
    "entry_pending" => %w[partially_filled filled rejected],
    "partially_filled" => %w[partially_filled filled exit_pending rejected],
    "filled" => %w[exit_pending liquidated],
    "exit_pending" => %w[closed liquidated],
    "closed" => [],
    "liquidated" => [],
    "rejected" => []
  }.freeze

  before_validation :set_default_status

  class InvalidTransitionError < StandardError; end

  # Moves the position to a new lifecycle state.
  # @param next_state [String] target state.
  # @raise [InvalidTransitionError] when transition is not allowed.
  # @return [Boolean]
  def transition_to!(next_state)
    next_state = next_state.to_s
    allowed = TRANSITIONS.fetch(status.to_s)
    raise InvalidTransitionError, "#{status} -> #{next_state} is invalid" unless allowed.include?(next_state)

    update!(status: next_state)
  end

  # Recalculates position deterministically from persisted fills.
  # @return [Position]
  def recalculate_from_orders!
    Trading::PositionRecalculator.call(id)
  end

  private

  def set_default_status
    self.status ||= "init"
  end
end
