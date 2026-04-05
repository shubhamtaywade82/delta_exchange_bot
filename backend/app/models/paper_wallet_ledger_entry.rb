# frozen_string_literal: true

class PaperWalletLedgerEntry < ApplicationRecord
  belongs_to :paper_wallet
  belongs_to :reference, polymorphic: true, optional: true

  before_validation :assign_default_sub_type

  ENTRY_TYPES = %w[
    deposit
    withdrawal
    margin_reserved
    margin_released
    realized_pnl
    commission
    funding
  ].freeze

  DIRECTIONS = %w[debit credit].freeze

  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :amount_inr, presence: true
  validates :sub_type, presence: true
  validates :external_ref, uniqueness: { scope: [ :paper_wallet_id, :entry_type, :sub_type ] }, allow_nil: true

  private

  def assign_default_sub_type
    self.sub_type ||= case entry_type
    when "margin_reserved" then "margin_lock"
    when "margin_released" then "margin_release"
    when "commission" then "fee"
    when "realized_pnl" then "pnl"
    else entry_type
    end
  end
end
