# frozen_string_literal: true

class AddIndexSymbolConfigsOnEnabled < ActiveRecord::Migration[8.1]
  def change
    add_index :symbol_configs, :enabled, if_not_exists: true
  end
end
