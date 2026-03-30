# frozen_string_literal: true

# Order tracks exchange lifecycle for a single execution instruction.
# Position state should be derived from linked order states/fills.
class Order < ApplicationRecord
  belongs_to :trading_session
  belongs_to :position, optional: true
  has_many :fills, dependent: :destroy

  STATES = %w[created submitted partially_filled filled cancelled rejected].freeze
  SIDES  = %w[buy sell].freeze
  TRANSITIONS = {
    "created" => %w[submitted cancelled rejected],
    "submitted" => %w[partially_filled filled cancelled rejected],
    "partially_filled" => %w[partially_filled filled cancelled],
    "filled" => [],
    "cancelled" => [],
    "rejected" => []
  }.freeze

  validates :symbol, presence: true
  validates :side, inclusion: { in: SIDES }
  validates :size, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATES }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :client_order_id, presence: true, uniqueness: true

  class InvalidTransitionError < StandardError; end

  # Transition order state with allowed lifecycle guardrails.
  # @param next_state [String]
  # @return [void]
  def transition_to!(next_state)
    target = next_state.to_s
    allowed = TRANSITIONS.fetch(status)
    raise InvalidTransitionError, "#{status} -> #{target} is invalid" unless allowed.include?(target)

    update!(status: target)
  end

  # Applies exchange-consistent fill aggregation and status update.
  # @param cumulative_qty [Numeric]
  # @param avg_fill_price [Numeric]
  # @param exchange_status [String]
  # @return [void]
  def apply_fill!(cumulative_qty:, avg_fill_price:, exchange_status:)
    qty = BigDecimal(cumulative_qty.to_s)
    raise ArgumentError, "cumulative_qty cannot decrease" if filled_qty.present? && qty < filled_qty

    self.filled_qty = qty
    self.avg_fill_price = avg_fill_price if avg_fill_price.present?

    self.status = if qty >= size.to_d
                    "filled"
                  elsif qty.positive?
                    "partially_filled"
                  else
                    normalize_status(exchange_status)
                  end
    save!
  end

  def filled?
    status == "filled"
  end

  def open?
    status.in?(%w[created submitted partially_filled])
  end

  def terminal?
    status.in?(%w[filled cancelled rejected])
  end

  private

  def normalize_status(exchange_status)
    case exchange_status.to_s
    when "open", "pending", "submitted"
      "submitted"
    when "cancelled", "canceled"
      "cancelled"
    when "rejected"
      "rejected"
    when "filled"
      "filled"
    else
      status.presence || "created"
    end
  end
end
