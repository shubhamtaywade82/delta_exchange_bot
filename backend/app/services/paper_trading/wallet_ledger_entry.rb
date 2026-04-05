# frozen_string_literal: true

module PaperTrading
  # Typed writer around PaperWalletLedgerEntry to keep ledger verbs explicit.
  class WalletLedgerEntry
    def initialize(wallet:)
      @wallet = wallet
    end

    def deposit!(amount_inr:, reference: nil, meta: {})
      write!(entry_type: "deposit", sub_type: "deposit", direction: "credit", amount_inr:, reference:, meta:)
    end

    def margin_lock!(amount_inr:, reference: nil, meta: {})
      write!(entry_type: "margin_reserved", sub_type: "margin_lock", direction: "debit", amount_inr:, reference:, meta:)
    end

    def margin_release!(amount_inr:, reference: nil, meta: {})
      write!(entry_type: "margin_released", sub_type: "margin_release", direction: "credit", amount_inr:, reference:, meta:)
    end

    def fee!(amount_inr:, reference: nil, meta: {})
      write!(entry_type: "commission", sub_type: "fee", direction: "debit", amount_inr:, reference:, meta:)
    end

    def funding!(amount_inr:, reference: nil, meta: {})
      direction = amount_inr.to_d.negative? ? "debit" : "credit"
      write!(entry_type: "funding", sub_type: "funding", direction:, amount_inr: amount_inr.to_d.abs, reference:, meta:)
    end

    def pnl_realized!(amount_inr:, reference: nil, meta: {})
      direction = amount_inr.to_d.negative? ? "debit" : "credit"
      write!(entry_type: "realized_pnl", sub_type: "pnl", direction:, amount_inr: amount_inr.to_d.abs, reference:, meta:)
    end

    private

    def write!(entry_type:, sub_type:, direction:, amount_inr:, reference:, meta:)
      @wallet.paper_wallet_ledger_entries.create!(
        entry_type:,
        sub_type:,
        direction:,
        amount_inr: amount_inr.to_d.round(2),
        reference:,
        meta: meta.stringify_keys
      )
    end
  end
end
