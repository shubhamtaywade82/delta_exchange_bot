class AddAdaptiveFieldsToTrades < ActiveRecord::Migration[8.1]
  def up
    add_column :trades, :expected_edge, :decimal, precision: 12, scale: 6
    add_column :trades, :realized_edge, :decimal, precision: 12, scale: 6
    add_column :trades, :regime, :string
    add_column :trades, :strategy, :string

    add_index :trades, :regime
    add_index :trades, :strategy
  end

  def down
    remove_index :trades, :strategy if index_exists?(:trades, :strategy)
    remove_index :trades, :regime if index_exists?(:trades, :regime)

    remove_column :trades, :strategy if column_exists?(:trades, :strategy)
    remove_column :trades, :regime if column_exists?(:trades, :regime)
    remove_column :trades, :realized_edge if column_exists?(:trades, :realized_edge)
    remove_column :trades, :expected_edge if column_exists?(:trades, :expected_edge)
  end
end
