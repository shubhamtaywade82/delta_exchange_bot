class CreatePositions < ActiveRecord::Migration[8.1]
  def change
    create_table :positions do |t|
      t.string :symbol
      t.string :side
      t.string :status
      t.decimal :entry_price
      t.decimal :exit_price
      t.decimal :size
      t.integer :leverage
      t.decimal :margin
      t.decimal :pnl_usd
      t.decimal :pnl_inr
      t.datetime :entry_time
      t.datetime :exit_time
      t.integer :product_id
      t.decimal :peak_price
      t.decimal :trail_pct

      t.timestamps
    end
  end
end
