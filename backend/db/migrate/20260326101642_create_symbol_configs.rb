class CreateSymbolConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :symbol_configs do |t|
      t.string :symbol
      t.integer :leverage
      t.boolean :enabled

      t.timestamps
    end
  end
end
