class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :key
      t.string :value
      t.string :value_type

      t.timestamps
    end
  end
end
