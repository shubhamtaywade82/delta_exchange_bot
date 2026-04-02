# frozen_string_literal: true

class PaperWalletInrLedgerAndRr < ActiveRecord::Migration[8.1]
  BACKFILL_USD_INR = 85.0

  def up
    add_column :paper_wallets, :balance_inr, :decimal, precision: 20, scale: 2, null: false, default: "0"
    add_column :paper_wallets, :available_inr, :decimal, precision: 20, scale: 2, null: false, default: "0"
    add_column :paper_wallets, :used_margin_inr, :decimal, precision: 20, scale: 2, null: false, default: "0"
    add_column :paper_wallets, :equity_inr, :decimal, precision: 20, scale: 2, null: false, default: "0"
    add_column :paper_wallets, :unrealized_pnl_inr, :decimal, precision: 20, scale: 2, null: false, default: "0"
    add_column :paper_wallets, :realized_pnl_inr, :decimal, precision: 20, scale: 2, null: false, default: "0"

    add_column :paper_wallet_ledger_entries, :amount_inr, :decimal, precision: 20, scale: 2
    add_column :paper_wallet_ledger_entries, :meta, :jsonb, null: false, default: {}

    execute <<~SQL.squish
      UPDATE paper_wallet_ledger_entries
      SET amount_inr = ROUND((amount * #{BACKFILL_USD_INR})::numeric, 2)
    SQL

    change_column_null :paper_wallet_ledger_entries, :amount_inr, false

    execute <<~SQL.squish
      UPDATE paper_wallets SET
        balance_inr = ROUND(((cash_balance + realized_pnl) * #{BACKFILL_USD_INR})::numeric, 2),
        used_margin_inr = ROUND((reserved_margin * #{BACKFILL_USD_INR})::numeric, 2),
        unrealized_pnl_inr = ROUND((unrealized_pnl * #{BACKFILL_USD_INR})::numeric, 2),
        realized_pnl_inr = ROUND((realized_pnl * #{BACKFILL_USD_INR})::numeric, 2),
        equity_inr = ROUND((equity * #{BACKFILL_USD_INR})::numeric, 2),
        available_inr = GREATEST(0, ROUND(((equity - reserved_margin - unrealized_pnl) * #{BACKFILL_USD_INR})::numeric, 2))
    SQL

    change_column_null :paper_trading_signals, :risk_pct, true
    add_column :paper_trading_signals, :max_loss_inr, :decimal, precision: 20, scale: 2, null: false, default: "5000"
  end

  def down
    remove_column :paper_trading_signals, :max_loss_inr
    change_column_null :paper_trading_signals, :risk_pct, false

    remove_column :paper_wallet_ledger_entries, :meta
    remove_column :paper_wallet_ledger_entries, :amount_inr

    remove_column :paper_wallets, :realized_pnl_inr
    remove_column :paper_wallets, :unrealized_pnl_inr
    remove_column :paper_wallets, :equity_inr
    remove_column :paper_wallets, :used_margin_inr
    remove_column :paper_wallets, :available_inr
    remove_column :paper_wallets, :balance_inr
  end
end
