class AddPositionReconciliationFields < ActiveRecord::Migration[8.1]
  def up
    add_column :positions, :needs_reconciliation, :boolean, null: false, default: false
    add_column :positions, :lock_version, :integer, null: false, default: 0

    add_index :positions, :needs_reconciliation
  end

  def down
    remove_index :positions, :needs_reconciliation if index_exists?(:positions, :needs_reconciliation)
    remove_column :positions, :lock_version if column_exists?(:positions, :lock_version)
    remove_column :positions, :needs_reconciliation if column_exists?(:positions, :needs_reconciliation)
  end
end
