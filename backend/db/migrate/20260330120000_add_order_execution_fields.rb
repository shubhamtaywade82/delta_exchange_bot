class AddOrderExecutionFields < ActiveRecord::Migration[8.1]
  def up
    add_reference :orders, :position, foreign_key: true, index: true
    add_column :orders, :client_order_id, :string
    add_column :orders, :last_fill_digest, :string

    add_index :orders, :client_order_id, unique: true
  end

  def down
    remove_index :orders, :client_order_id if index_exists?(:orders, :client_order_id)
    remove_column :orders, :last_fill_digest if column_exists?(:orders, :last_fill_digest)
    remove_column :orders, :client_order_id if column_exists?(:orders, :client_order_id)
    remove_reference :orders, :position, foreign_key: true if column_exists?(:orders, :position_id)
  end
end
