class CreateTrades < ActiveRecord::Migration[8.1]
  def change
    create_table :trades do |t|
      t.string :symbol
      t.string :side
      t.decimal :entry_price
      t.decimal :exit_price
      t.decimal :size
      t.decimal :pnl_usd
      t.decimal :pnl_inr
      t.integer :duration_seconds
      t.datetime :closed_at

      t.timestamps
    end
  end
end
