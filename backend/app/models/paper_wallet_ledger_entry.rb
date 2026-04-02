# frozen_string_literal: true

class PaperWalletLedgerEntry < ApplicationRecord
  belongs_to :paper_wallet
  belongs_to :reference, polymorphic: true, optional: true

  ENTRY_TYPES = %w[
    margin_reserved
    margin_released
    realized_pnl
    commission
  ].freeze

  DIRECTIONS = %w[debit credit].freeze

  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :amount, presence: true
end
