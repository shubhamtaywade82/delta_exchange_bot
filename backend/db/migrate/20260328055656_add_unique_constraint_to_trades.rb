class AddUniqueConstraintToTrades < ActiveRecord::Migration[8.1]
  def change
    add_index :trades, [:symbol, :entry_price, :exit_price, :closed_at], unique: true, name: 'index_trades_uniqueness'
  end
end
