# frozen_string_literal: true

class CreateSettingChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :setting_changes do |t|
      t.references :setting, null: false, foreign_key: true
      t.string :key, null: false
      t.string :old_value
      t.string :new_value, null: false
      t.string :old_value_type
      t.string :new_value_type, null: false
      t.string :source, null: false
      t.string :reason
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :setting_changes, [:key, :created_at]
    add_index :setting_changes, :source
  end
end
