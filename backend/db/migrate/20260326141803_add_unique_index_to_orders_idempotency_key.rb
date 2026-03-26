class AddUniqueIndexToOrdersIdempotencyKey < ActiveRecord::Migration[8.1]
  def change
    add_index :orders, :idempotency_key, unique: true
    add_index :orders, :exchange_order_id
  end
end
