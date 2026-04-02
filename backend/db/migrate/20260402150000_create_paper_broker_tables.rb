# frozen_string_literal: true

class CreatePaperBrokerTables < ActiveRecord::Migration[8.1]
  def change
    create_table :paper_wallets do |t|
      t.string :name, null: false, default: "default"
      t.decimal :cash_balance, precision: 36, scale: 18, null: false, default: "0"
      t.decimal :realized_pnl, precision: 36, scale: 18, null: false, default: "0"
      t.decimal :unrealized_pnl, precision: 36, scale: 18, null: false, default: "0"
      t.decimal :equity, precision: 36, scale: 18, null: false, default: "0"
      t.decimal :reserved_margin, precision: 36, scale: 18, null: false, default: "0"
      t.timestamps
    end

    create_table :paper_product_snapshots do |t|
      t.integer :product_id, null: false
      t.string :symbol, null: false
      t.string :contract_type
      t.string :settling_asset
      t.string :notional_type
      t.decimal :contract_value, precision: 36, scale: 18, null: false
      t.decimal :risk_unit_per_contract, precision: 36, scale: 18, null: false
      t.string :valuation_strategy, null: false, default: "contract_linear"
      t.decimal :tick_size, precision: 36, scale: 18, null: false
      t.integer :position_size_limit
      t.decimal :mark_price, precision: 36, scale: 18
      t.decimal :close_price, precision: 36, scale: 18
      t.jsonb :raw_metadata, default: {}, null: false
      t.timestamps
    end
    add_index :paper_product_snapshots, :product_id, unique: true
    add_index :paper_product_snapshots, :symbol, unique: true

    create_table :paper_trading_signals do |t|
      t.references :paper_wallet, null: false, foreign_key: true
      t.integer :product_id, null: false
      t.string :side, null: false
      t.decimal :entry_price, precision: 36, scale: 18, null: false
      t.decimal :stop_price, precision: 36, scale: 18, null: false
      t.decimal :risk_pct, precision: 16, scale: 10, null: false
      t.string :status, null: false, default: "pending"
      t.string :rejection_reason
      t.string :idempotency_key, null: false
      t.timestamps
    end
    add_index :paper_trading_signals, :idempotency_key, unique: true
    add_index :paper_trading_signals, %i[paper_wallet_id status]

    create_table :paper_orders do |t|
      t.references :paper_wallet, null: false, foreign_key: true
      t.references :paper_product_snapshot, null: false, foreign_key: true
      t.references :paper_trading_signal, null: false, foreign_key: true
      t.string :side, null: false
      t.string :order_type, null: false
      t.integer :size, null: false
      t.decimal :limit_price, precision: 36, scale: 18
      t.decimal :avg_fill_price, precision: 36, scale: 18
      t.string :state, null: false
      t.string :client_order_id, null: false
      t.timestamps
    end
    add_index :paper_orders, :client_order_id, unique: true

    create_table :paper_fills do |t|
      t.references :paper_order, null: false, foreign_key: true
      t.integer :size, null: false
      t.decimal :price, precision: 36, scale: 18, null: false
      t.datetime :filled_at, null: false
      t.string :exchange_fill_id
      t.timestamps
    end
    add_index :paper_fills, :exchange_fill_id, unique: true, where: "exchange_fill_id IS NOT NULL"

    create_table :paper_positions do |t|
      t.references :paper_wallet, null: false, foreign_key: true
      t.references :paper_product_snapshot, null: false, foreign_key: true
      t.string :side, null: false
      t.integer :net_quantity, null: false, default: 0
      t.decimal :avg_entry_price, precision: 36, scale: 18, null: false
      t.decimal :risk_unit_per_contract, precision: 36, scale: 18, null: false
      t.timestamps
    end
    add_index :paper_positions, %i[paper_wallet_id paper_product_snapshot_id], unique: true,
              name: "index_paper_positions_on_wallet_and_product"

    create_table :paper_wallet_ledger_entries do |t|
      t.references :paper_wallet, null: false, foreign_key: true
      t.string :entry_type, null: false
      t.string :direction, null: false
      t.decimal :amount, precision: 36, scale: 18, null: false
      t.references :reference, polymorphic: true, null: true
      t.string :notes
      t.timestamps
    end
    add_index :paper_wallet_ledger_entries, %i[paper_wallet_id entry_type]
    add_index :paper_wallet_ledger_entries, %i[reference_type reference_id entry_type],
              unique: true, name: "index_paper_ledger_ref_entry_unique"
  end
end
