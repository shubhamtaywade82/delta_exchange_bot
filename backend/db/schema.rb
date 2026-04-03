# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_03_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "fills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "exchange_fill_id", null: false
    t.decimal "fee", precision: 20, scale: 8
    t.datetime "filled_at", null: false
    t.bigint "order_id", null: false
    t.decimal "price", precision: 20, scale: 8
    t.decimal "quantity", precision: 20, scale: 8, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["exchange_fill_id"], name: "index_fills_on_exchange_fill_id", unique: true
    t.index ["order_id", "filled_at", "exchange_fill_id"], name: "index_fills_ordered_execution"
    t.index ["order_id", "filled_at"], name: "index_fills_on_order_id_and_filled_at"
    t.index ["order_id"], name: "index_fills_on_order_id"
    t.check_constraint "price IS NULL OR price > 0::numeric", name: "fills_price_positive"
    t.check_constraint "quantity > 0::numeric", name: "fills_quantity_positive"
  end

  create_table "generated_signals", force: :cascade do |t|
    t.bigint "candle_timestamp", null: false
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.decimal "entry_price", precision: 20, scale: 8, null: false
    t.string "error_message"
    t.decimal "risk_pct", precision: 8, scale: 6
    t.string "side", null: false
    t.string "source", null: false
    t.string "status", default: "generated", null: false
    t.decimal "stop_price", precision: 24, scale: 8
    t.string "strategy", null: false
    t.string "symbol", null: false
    t.bigint "trading_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_generated_signals_on_status"
    t.index ["symbol", "candle_timestamp"], name: "index_generated_signals_on_symbol_and_candle_timestamp"
    t.index ["trading_session_id", "created_at"], name: "index_generated_signals_on_trading_session_id_and_created_at"
    t.index ["trading_session_id"], name: "index_generated_signals_on_trading_session_id"
  end

  create_table "orders", force: :cascade do |t|
    t.decimal "avg_fill_price"
    t.string "client_order_id"
    t.datetime "created_at", null: false
    t.string "exchange_order_id"
    t.decimal "filled_qty"
    t.string "idempotency_key"
    t.string "last_fill_digest"
    t.string "order_type"
    t.bigint "portfolio_id", null: false
    t.bigint "position_id"
    t.decimal "price"
    t.jsonb "raw_payload"
    t.string "side"
    t.decimal "size"
    t.string "status"
    t.string "symbol"
    t.bigint "trading_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["client_order_id"], name: "index_orders_on_client_order_id", unique: true
    t.index ["exchange_order_id"], name: "index_orders_on_exchange_order_id"
    t.index ["idempotency_key"], name: "index_orders_on_idempotency_key", unique: true
    t.index ["portfolio_id"], name: "index_orders_on_portfolio_id"
    t.index ["position_id"], name: "index_orders_on_position_id"
    t.index ["trading_session_id"], name: "index_orders_on_trading_session_id"
    t.check_constraint "filled_qty IS NULL OR size IS NULL OR filled_qty <= size", name: "orders_no_overfill"
  end

  create_table "paper_fills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "exchange_fill_id"
    t.datetime "filled_at", null: false
    t.bigint "paper_order_id", null: false
    t.decimal "price", precision: 36, scale: 18, null: false
    t.integer "size", null: false
    t.datetime "updated_at", null: false
    t.index ["exchange_fill_id"], name: "index_paper_fills_on_exchange_fill_id", unique: true, where: "(exchange_fill_id IS NOT NULL)"
    t.index ["paper_order_id"], name: "index_paper_fills_on_paper_order_id"
  end

  create_table "paper_orders", force: :cascade do |t|
    t.decimal "avg_fill_price", precision: 36, scale: 18
    t.string "client_order_id", null: false
    t.datetime "created_at", null: false
    t.decimal "limit_price", precision: 36, scale: 18
    t.string "order_type", null: false
    t.bigint "paper_product_snapshot_id", null: false
    t.bigint "paper_trading_signal_id", null: false
    t.bigint "paper_wallet_id", null: false
    t.string "side", null: false
    t.integer "size", null: false
    t.string "state", null: false
    t.datetime "updated_at", null: false
    t.index ["client_order_id"], name: "index_paper_orders_on_client_order_id", unique: true
    t.index ["paper_product_snapshot_id"], name: "index_paper_orders_on_paper_product_snapshot_id"
    t.index ["paper_trading_signal_id"], name: "index_paper_orders_on_paper_trading_signal_id"
    t.index ["paper_wallet_id"], name: "index_paper_orders_on_paper_wallet_id"
  end

  create_table "paper_positions", force: :cascade do |t|
    t.decimal "avg_entry_price", precision: 36, scale: 18, null: false
    t.datetime "created_at", null: false
    t.integer "leverage", default: 1, null: false
    t.integer "net_quantity", default: 0, null: false
    t.bigint "paper_product_snapshot_id", null: false
    t.bigint "paper_wallet_id", null: false
    t.decimal "risk_unit_per_contract", precision: 36, scale: 18, null: false
    t.string "side", null: false
    t.datetime "updated_at", null: false
    t.index ["paper_product_snapshot_id"], name: "index_paper_positions_on_paper_product_snapshot_id"
    t.index ["paper_wallet_id", "paper_product_snapshot_id"], name: "index_paper_positions_on_wallet_and_product", unique: true
    t.index ["paper_wallet_id"], name: "index_paper_positions_on_paper_wallet_id"
  end

  create_table "paper_product_snapshots", force: :cascade do |t|
    t.decimal "close_price", precision: 36, scale: 18
    t.string "contract_type"
    t.decimal "contract_value", precision: 36, scale: 18, null: false
    t.datetime "created_at", null: false
    t.integer "default_leverage"
    t.decimal "mark_price", precision: 36, scale: 18
    t.string "notional_type"
    t.integer "position_size_limit"
    t.integer "product_id", null: false
    t.jsonb "raw_metadata", default: {}, null: false
    t.decimal "risk_unit_per_contract", precision: 36, scale: 18, null: false
    t.string "settling_asset"
    t.string "symbol", null: false
    t.decimal "tick_size", precision: 36, scale: 18, null: false
    t.datetime "updated_at", null: false
    t.string "valuation_strategy", default: "contract_linear", null: false
    t.index ["product_id"], name: "index_paper_product_snapshots_on_product_id", unique: true
    t.index ["symbol"], name: "index_paper_product_snapshots_on_symbol", unique: true
  end

  create_table "paper_trading_signals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "entry_price", precision: 36, scale: 18, null: false
    t.string "idempotency_key", null: false
    t.decimal "max_loss_inr", precision: 20, scale: 2, default: "5000.0", null: false
    t.bigint "paper_wallet_id", null: false
    t.integer "product_id", null: false
    t.string "rejection_reason"
    t.decimal "risk_pct", precision: 16, scale: 10
    t.string "side", null: false
    t.string "status", default: "pending", null: false
    t.decimal "stop_price", precision: 36, scale: 18, null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_paper_trading_signals_on_idempotency_key", unique: true
    t.index ["paper_wallet_id", "status"], name: "index_paper_trading_signals_on_paper_wallet_id_and_status"
    t.index ["paper_wallet_id"], name: "index_paper_trading_signals_on_paper_wallet_id"
  end

  create_table "paper_wallet_ledger_entries", force: :cascade do |t|
    t.decimal "amount_inr", precision: 20, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.string "entry_type", null: false
    t.jsonb "meta", default: {}, null: false
    t.string "notes"
    t.bigint "paper_wallet_id", null: false
    t.bigint "reference_id"
    t.string "reference_type"
    t.datetime "updated_at", null: false
    t.index ["paper_wallet_id", "entry_type"], name: "idx_on_paper_wallet_id_entry_type_b03b77b663"
    t.index ["paper_wallet_id"], name: "index_paper_wallet_ledger_entries_on_paper_wallet_id"
    t.index ["reference_type", "reference_id"], name: "index_paper_ledger_on_reference"
    t.index ["reference_type", "reference_id"], name: "index_paper_wallet_ledger_entries_on_reference"
  end

  create_table "paper_wallets", force: :cascade do |t|
    t.decimal "available_inr", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "balance_inr", precision: 20, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "equity_inr", precision: 20, scale: 2, default: "0.0", null: false
    t.string "name", default: "default", null: false
    t.decimal "realized_pnl_inr", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "unrealized_pnl_inr", precision: 20, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.decimal "used_margin_inr", precision: 20, scale: 2, default: "0.0", null: false
  end

  create_table "portfolio_ledger_entries", force: :cascade do |t|
    t.decimal "balance_delta", precision: 20, scale: 8, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.bigint "fill_id", null: false
    t.bigint "portfolio_id", null: false
    t.decimal "realized_pnl_delta", precision: 20, scale: 8, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["fill_id"], name: "index_portfolio_ledger_entries_on_fill_id", unique: true
    t.index ["portfolio_id"], name: "index_portfolio_ledger_entries_on_portfolio_id"
  end

  create_table "portfolios", force: :cascade do |t|
    t.decimal "available_balance", precision: 20, scale: 8, default: "0.0", null: false
    t.decimal "balance", precision: 20, scale: 8, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "used_margin", precision: 20, scale: 8, default: "0.0", null: false
  end

  create_table "positions", force: :cascade do |t|
    t.decimal "contract_value"
    t.datetime "created_at", null: false
    t.jsonb "entry_features", default: {}
    t.decimal "entry_price"
    t.datetime "entry_time"
    t.decimal "exit_price"
    t.datetime "exit_time"
    t.decimal "fee_total", precision: 16, scale: 6, default: "0.0"
    t.integer "leverage"
    t.decimal "liquidation_price"
    t.integer "lock_version", default: 0, null: false
    t.decimal "margin"
    t.boolean "needs_reconciliation", default: false, null: false
    t.decimal "peak_price"
    t.decimal "pnl_inr"
    t.decimal "pnl_usd"
    t.bigint "portfolio_id", null: false
    t.integer "product_id"
    t.string "regime"
    t.string "side"
    t.decimal "size"
    t.string "status"
    t.decimal "stop_price"
    t.string "strategy"
    t.string "symbol"
    t.decimal "trail_pct"
    t.decimal "unrealized_pnl_usd", precision: 20, scale: 8
    t.datetime "updated_at", null: false
    t.index ["needs_reconciliation"], name: "index_positions_on_needs_reconciliation"
    t.index ["portfolio_id", "symbol"], name: "idx_positions_one_open_net_per_portfolio_symbol", unique: true, where: "((status)::text = ANY (ARRAY[('init'::character varying)::text, ('entry_pending'::character varying)::text, ('partially_filled'::character varying)::text, ('filled'::character varying)::text, ('exit_pending'::character varying)::text, ('open'::character varying)::text]))"
    t.index ["portfolio_id"], name: "index_positions_on_portfolio_id"
  end

  create_table "setting_changes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "new_value", null: false
    t.string "new_value_type", null: false
    t.string "old_value"
    t.string "old_value_type"
    t.string "reason"
    t.bigint "setting_id", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["key", "created_at"], name: "index_setting_changes_on_key_and_created_at"
    t.index ["setting_id"], name: "index_setting_changes_on_setting_id"
    t.index ["source"], name: "index_setting_changes_on_source"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.string "value"
    t.string "value_type"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "strategy_params", force: :cascade do |t|
    t.decimal "aggression", precision: 6, scale: 4, default: "0.5"
    t.decimal "alpha", precision: 8, scale: 6, default: "0.01"
    t.decimal "bias", precision: 10, scale: 6, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "regime", null: false
    t.decimal "risk_multiplier", precision: 6, scale: 4, default: "1.0"
    t.string "strategy", null: false
    t.datetime "updated_at", null: false
    t.index ["strategy", "regime"], name: "index_strategy_params_on_strategy_and_regime", unique: true
  end

  create_table "symbol_configs", force: :cascade do |t|
    t.string "contract_type"
    t.datetime "created_at", null: false
    t.boolean "enabled"
    t.datetime "fetched_at"
    t.decimal "last_close_price", precision: 24, scale: 8
    t.decimal "last_mark_price", precision: 24, scale: 8
    t.integer "leverage"
    t.jsonb "metadata", default: {}, null: false
    t.integer "product_id"
    t.string "symbol"
    t.decimal "tick_size", precision: 24, scale: 12
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_symbol_configs_on_enabled"
  end

  create_table "trades", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.decimal "entry_price"
    t.decimal "exit_price"
    t.decimal "expected_edge", precision: 12, scale: 6, default: "0.0"
    t.jsonb "features", default: {}
    t.decimal "fees", precision: 16, scale: 6, default: "0.0"
    t.integer "holding_time_ms", default: 0
    t.decimal "pnl_inr"
    t.decimal "pnl_usd"
    t.bigint "portfolio_id"
    t.decimal "realized_edge", precision: 12, scale: 6
    t.decimal "realized_pnl", precision: 16, scale: 6, default: "0.0"
    t.string "regime", null: false
    t.string "side"
    t.decimal "size"
    t.string "strategy", null: false
    t.string "symbol"
    t.datetime "updated_at", null: false
    t.index ["portfolio_id"], name: "index_trades_on_portfolio_id"
    t.index ["regime"], name: "index_trades_on_regime"
    t.index ["strategy", "regime"], name: "index_trades_on_strategy_and_regime"
    t.index ["strategy"], name: "index_trades_on_strategy"
    t.index ["symbol", "entry_price", "exit_price", "closed_at"], name: "index_trades_uniqueness", unique: true
  end

  create_table "trading_sessions", force: :cascade do |t|
    t.decimal "capital"
    t.datetime "created_at", null: false
    t.integer "leverage"
    t.bigint "portfolio_id", null: false
    t.datetime "started_at"
    t.string "status"
    t.datetime "stopped_at"
    t.string "strategy"
    t.datetime "updated_at", null: false
    t.index ["portfolio_id"], name: "index_trading_sessions_on_portfolio_id"
  end

  add_foreign_key "fills", "orders"
  add_foreign_key "generated_signals", "trading_sessions"
  add_foreign_key "orders", "portfolios"
  add_foreign_key "orders", "positions"
  add_foreign_key "orders", "trading_sessions"
  add_foreign_key "paper_fills", "paper_orders"
  add_foreign_key "paper_orders", "paper_product_snapshots"
  add_foreign_key "paper_orders", "paper_trading_signals"
  add_foreign_key "paper_orders", "paper_wallets"
  add_foreign_key "paper_positions", "paper_product_snapshots"
  add_foreign_key "paper_positions", "paper_wallets"
  add_foreign_key "paper_trading_signals", "paper_wallets"
  add_foreign_key "paper_wallet_ledger_entries", "paper_wallets"
  add_foreign_key "portfolio_ledger_entries", "fills"
  add_foreign_key "portfolio_ledger_entries", "portfolios"
  add_foreign_key "positions", "portfolios"
  add_foreign_key "setting_changes", "settings"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "trades", "portfolios"
  add_foreign_key "trading_sessions", "portfolios"
end
