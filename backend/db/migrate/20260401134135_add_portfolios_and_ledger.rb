# frozen_string_literal: true

class AddPortfoliosAndLedger < ActiveRecord::Migration[8.1]
  ACTIVE_NET_STATUSES = %w[init entry_pending partially_filled filled exit_pending open].freeze

  def up
    create_table :portfolios do |t|
      t.decimal :balance, precision: 20, scale: 8, default: "0", null: false
      t.decimal :available_balance, precision: 20, scale: 8, default: "0", null: false
      t.decimal :used_margin, precision: 20, scale: 8, default: "0", null: false
      t.timestamps
    end

    create_table :portfolio_ledger_entries do |t|
      t.references :portfolio, null: false, foreign_key: true
      t.references :fill, null: false, foreign_key: true, index: { unique: true }
      t.decimal :realized_pnl_delta, precision: 20, scale: 8, default: "0", null: false
      t.decimal :balance_delta, precision: 20, scale: 8, default: "0", null: false
      t.timestamps
    end

    add_reference :trading_sessions, :portfolio, foreign_key: true
    add_reference :orders, :portfolio, foreign_key: true
    add_reference :positions, :portfolio, foreign_key: true
    add_column :positions, :unrealized_pnl_usd, :decimal, precision: 20, scale: 8

    remove_index :positions, name: "index_positions_on_symbol_when_open", if_exists: true

    say_with_time "backfill portfolios and foreign keys" do
      backfill_portfolios!
      backfill_order_portfolios!
      backfill_position_portfolios!
      dedupe_active_positions_per_portfolio_symbol!
    end

    change_column_null :trading_sessions, :portfolio_id, false
    change_column_null :orders, :portfolio_id, false
    change_column_null :positions, :portfolio_id, false

    add_index :positions, %i[portfolio_id symbol],
              unique: true,
              name: "idx_positions_one_open_net_per_portfolio_symbol",
              where: "status IN ('init','entry_pending','partially_filled','filled','exit_pending','open')"
  end

  def down
    remove_index :positions, name: "idx_positions_one_open_net_per_portfolio_symbol", if_exists: true

    change_column_null :trading_sessions, :portfolio_id, true
    change_column_null :orders, :portfolio_id, true
    change_column_null :positions, :portfolio_id, true

    remove_column :positions, :unrealized_pnl_usd, if_exists: true
    remove_reference :positions, :portfolio, foreign_key: true
    remove_reference :orders, :portfolio, foreign_key: true
    remove_reference :trading_sessions, :portfolio, foreign_key: true

    drop_table :portfolio_ledger_entries, if_exists: true
    drop_table :portfolios, if_exists: true

    add_index :positions, :symbol,
              name: "index_positions_on_symbol_when_open",
              unique: true,
              where: "((status)::text = 'open'::text)"
  end

  private

  def backfill_portfolios!
    TradingSession.reset_column_information
    TradingSession.find_each do |session|
      cap = session.read_attribute(:capital)
      initial = if cap.present? && BigDecimal(cap.to_s).positive?
                  BigDecimal(cap.to_s)
      else
                  BigDecimal("10000")
      end
      portfolio = Portfolio.create!(balance: initial, available_balance: initial, used_margin: 0)
      session.update_columns(portfolio_id: portfolio.id)
    end
  end

  def backfill_order_portfolios!
    Order.reset_column_information
    Order.where(portfolio_id: nil).find_each do |order|
      pid = TradingSession.where(id: order.trading_session_id).pick(:portfolio_id)
      raise "missing portfolio for session #{order.trading_session_id}" unless pid

      order.update_columns(portfolio_id: pid)
    end
  end

  def backfill_position_portfolios!
    Position.reset_column_information
    fallback = Portfolio.first&.id
    Position.where(portfolio_id: nil).find_each do |position|
      pid = Order.where(position_id: position.id).limit(1).pick(:portfolio_id)
      pid ||= fallback
      unless pid
        p = Portfolio.create!(balance: BigDecimal("0"), available_balance: BigDecimal("0"), used_margin: 0)
        fallback = p.id
        pid = p.id
      end
      position.update_columns(portfolio_id: pid)
    end
  end

  def dedupe_active_positions_per_portfolio_symbol!
    Position.reset_column_information
    scope = Position.where(status: ACTIVE_NET_STATUSES).where.not(portfolio_id: nil)
    scope.group_by { |p| [p.portfolio_id, p.symbol] }.each_value do |rows|
      next if rows.size <= 1

      keeper = rows.max_by { |r| [r.updated_at || Time.at(0), r.id] }
      rows.each do |r|
        next if r.id == keeper.id

        Order.where(position_id: r.id).update_all(position_id: keeper.id)
        r.update_columns(status: "closed", size: 0, entry_price: nil, margin: nil)
      end
    end
  end
end
