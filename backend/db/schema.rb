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

ActiveRecord::Schema[8.1].define(version: 2026_03_27_104051) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "orders", force: :cascade do |t|
    t.decimal "avg_fill_price"
    t.datetime "created_at", null: false
    t.string "exchange_order_id"
    t.decimal "filled_qty"
    t.string "idempotency_key"
    t.string "order_type"
    t.decimal "price"
    t.jsonb "raw_payload"
    t.string "side"
    t.decimal "size"
    t.string "status"
    t.string "symbol"
    t.bigint "trading_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["exchange_order_id"], name: "index_orders_on_exchange_order_id"
    t.index ["idempotency_key"], name: "index_orders_on_idempotency_key", unique: true
    t.index ["trading_session_id"], name: "index_orders_on_trading_session_id"
  end

  create_table "positions", force: :cascade do |t|
    t.decimal "contract_value"
    t.datetime "created_at", null: false
    t.decimal "entry_price"
    t.datetime "entry_time"
    t.decimal "exit_price"
    t.datetime "exit_time"
    t.integer "leverage"
    t.decimal "liquidation_price"
    t.decimal "margin"
    t.decimal "peak_price"
    t.decimal "pnl_inr"
    t.decimal "pnl_usd"
    t.integer "product_id"
    t.string "side"
    t.decimal "size"
    t.string "status"
    t.decimal "stop_price"
    t.string "symbol"
    t.decimal "trail_pct"
    t.datetime "updated_at", null: false
    t.index ["symbol"], name: "index_positions_on_symbol_when_open", unique: true, where: "((status)::text = 'open'::text)"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.string "value"
    t.string "value_type"
  end

  create_table "symbol_configs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled"
    t.integer "leverage"
    t.string "symbol"
    t.datetime "updated_at", null: false
  end

  create_table "trades", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.decimal "entry_price"
    t.decimal "exit_price"
    t.decimal "pnl_inr"
    t.decimal "pnl_usd"
    t.string "side"
    t.decimal "size"
    t.string "symbol"
    t.datetime "updated_at", null: false
  end

  create_table "trading_sessions", force: :cascade do |t|
    t.decimal "capital"
    t.datetime "created_at", null: false
    t.integer "leverage"
    t.datetime "started_at"
    t.string "status"
    t.datetime "stopped_at"
    t.string "strategy"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "orders", "trading_sessions"
end
