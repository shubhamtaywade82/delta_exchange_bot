class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :trading_session, null: false, foreign_key: true
      t.string :symbol
      t.string :side
      t.decimal :size
      t.decimal :price
      t.string :order_type
      t.string :status
      t.decimal :filled_qty
      t.decimal :avg_fill_price
      t.string :idempotency_key
      t.string :exchange_order_id
      t.jsonb :raw_payload

      t.timestamps
    end
  end
end
