class AddContractValueToPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :positions, :contract_value, :decimal
  end
end
