class AddProductIdToSymbolConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :symbol_configs, :product_id, :integer
  end
end
