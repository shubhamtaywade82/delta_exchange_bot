# frozen_string_literal: true

class AddExternalRefToPaperWalletLedgerEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :paper_wallet_ledger_entries, :external_ref, :string

    execute <<~SQL.squish
      UPDATE paper_wallet_ledger_entries
      SET external_ref = reference_type || ':' || reference_id::text
      WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL
    SQL

    add_index :paper_wallet_ledger_entries,
              [ :paper_wallet_id, :external_ref, :entry_type ],
              unique: true,
              name: "index_paper_wallet_ledger_idempotency",
              where: "external_ref IS NOT NULL"
  end

  def down
    remove_index :paper_wallet_ledger_entries, name: "index_paper_wallet_ledger_idempotency"
    remove_column :paper_wallet_ledger_entries, :external_ref
  end
end
