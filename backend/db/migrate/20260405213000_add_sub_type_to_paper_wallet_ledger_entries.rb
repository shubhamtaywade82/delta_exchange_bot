# frozen_string_literal: true

class AddSubTypeToPaperWalletLedgerEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :paper_wallet_ledger_entries, :sub_type, :string

    execute <<~SQL.squish
      UPDATE paper_wallet_ledger_entries
      SET sub_type = CASE entry_type
        WHEN 'margin_reserved' THEN 'margin_lock'
        WHEN 'margin_released' THEN 'margin_release'
        WHEN 'commission' THEN 'fee'
        WHEN 'realized_pnl' THEN 'pnl'
        ELSE entry_type
      END
    SQL

    change_column_null :paper_wallet_ledger_entries, :sub_type, false

    remove_index :paper_wallet_ledger_entries, name: "index_paper_wallet_ledger_idempotency"
    add_index :paper_wallet_ledger_entries,
              [ :paper_wallet_id, :external_ref, :entry_type, :sub_type ],
              unique: true,
              name: "index_paper_wallet_ledger_idempotency",
              where: "external_ref IS NOT NULL"
  end

  def down
    remove_index :paper_wallet_ledger_entries, name: "index_paper_wallet_ledger_idempotency"
    add_index :paper_wallet_ledger_entries,
              [ :paper_wallet_id, :external_ref, :entry_type ],
              unique: true,
              name: "index_paper_wallet_ledger_idempotency",
              where: "external_ref IS NOT NULL"

    remove_column :paper_wallet_ledger_entries, :sub_type
  end
end
