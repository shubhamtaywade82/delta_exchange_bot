class AddFillOrderingIndex < ActiveRecord::Migration[8.1]
  def up
    add_index :fills, [:order_id, :filled_at, :exchange_fill_id], name: "index_fills_ordered_execution"
  end

  def down
    remove_index :fills, name: "index_fills_ordered_execution" if index_exists?(:fills, [:order_id, :filled_at, :exchange_fill_id], name: "index_fills_ordered_execution")
  end
end
