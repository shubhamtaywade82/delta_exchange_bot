class AddOnlineLearningFields < ActiveRecord::Migration[8.1]
  def up
    add_column :trades, :realized_pnl, :decimal, precision: 16, scale: 6, default: 0 unless column_exists?(:trades, :realized_pnl)
    add_column :trades, :fees, :decimal, precision: 16, scale: 6, default: 0 unless column_exists?(:trades, :fees)
    add_column :trades, :holding_time_ms, :integer, default: 0 unless column_exists?(:trades, :holding_time_ms)
    add_column :trades, :features, :jsonb, default: {} unless column_exists?(:trades, :features)

    if column_exists?(:trades, :strategy)
      execute "UPDATE trades SET strategy = 'legacy' WHERE strategy IS NULL"
      change_column_null :trades, :strategy, false
    end

    if column_exists?(:trades, :regime)
      execute "UPDATE trades SET regime = 'unknown' WHERE regime IS NULL"
      change_column_null :trades, :regime, false
    end

    change_column_default :trades, :expected_edge, from: nil, to: 0 if column_exists?(:trades, :expected_edge)

    add_index :trades, %i[strategy regime], name: "index_trades_on_strategy_and_regime" unless index_exists?(:trades, %i[strategy regime], name: "index_trades_on_strategy_and_regime")

    create_table :strategy_params do |t|
      t.string :strategy, null: false
      t.string :regime, null: false
      t.decimal :alpha, precision: 8, scale: 6, default: 0.01
      t.decimal :aggression, precision: 6, scale: 4, default: 0.5
      t.decimal :risk_multiplier, precision: 6, scale: 4, default: 1.0
      t.decimal :bias, precision: 10, scale: 6, default: 0
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end

    add_index :strategy_params, %i[strategy regime], unique: true

    add_column :positions, :strategy, :string unless column_exists?(:positions, :strategy)
    add_column :positions, :regime, :string unless column_exists?(:positions, :regime)
    add_column :positions, :entry_features, :jsonb, default: {} unless column_exists?(:positions, :entry_features)
    add_column :positions, :fee_total, :decimal, precision: 16, scale: 6, default: 0 unless column_exists?(:positions, :fee_total)
  end

  def down
    remove_column :positions, :fee_total if column_exists?(:positions, :fee_total)
    remove_column :positions, :entry_features if column_exists?(:positions, :entry_features)
    remove_column :positions, :regime if column_exists?(:positions, :regime)
    remove_column :positions, :strategy if column_exists?(:positions, :strategy)

    remove_index :trades, name: "index_trades_on_strategy_and_regime" if index_exists?(:trades, name: "index_trades_on_strategy_and_regime")
    remove_column :trades, :features if column_exists?(:trades, :features)
    remove_column :trades, :holding_time_ms if column_exists?(:trades, :holding_time_ms)
    remove_column :trades, :fees if column_exists?(:trades, :fees)
    remove_column :trades, :realized_pnl if column_exists?(:trades, :realized_pnl)

    drop_table :strategy_params if table_exists?(:strategy_params)
  end
end
