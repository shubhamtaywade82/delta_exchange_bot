# frozen_string_literal: true

class ExtendSymbolConfigsForDeltaMetadata < ActiveRecord::Migration[8.1]
  def change
    change_table :symbol_configs, bulk: true do |t|
      t.decimal :tick_size, precision: 24, scale: 12
      t.string :contract_type
      t.jsonb :metadata, default: {}, null: false
      t.decimal :last_mark_price, precision: 24, scale: 8
      t.decimal :last_close_price, precision: 24, scale: 8
      t.datetime :fetched_at
    end
  end
end
