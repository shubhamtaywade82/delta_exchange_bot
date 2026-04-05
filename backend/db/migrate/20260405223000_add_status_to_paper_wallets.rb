# frozen_string_literal: true

class AddStatusToPaperWallets < ActiveRecord::Migration[8.1]
  def change
    add_column :paper_wallets, :status, :string, null: false, default: "active"
    add_index :paper_wallets, :status
  end
end
