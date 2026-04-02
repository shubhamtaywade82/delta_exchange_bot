# frozen_string_literal: true

class AdjustPaperLedgerIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :paper_wallet_ledger_entries, name: "index_paper_ledger_ref_entry_unique"
    add_index :paper_wallet_ledger_entries, %i[reference_type reference_id],
              name: "index_paper_ledger_on_reference"
  end
end
