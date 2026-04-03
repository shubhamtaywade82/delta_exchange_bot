# frozen_string_literal: true

class PaperWalletInrOnly < ActiveRecord::Migration[8.1]
  def change
    remove_column :paper_wallets, :cash_balance
    remove_column :paper_wallets, :realized_pnl
    remove_column :paper_wallets, :unrealized_pnl
    remove_column :paper_wallets, :equity
    remove_column :paper_wallets, :reserved_margin

    remove_column :paper_wallet_ledger_entries, :amount
  end
end
