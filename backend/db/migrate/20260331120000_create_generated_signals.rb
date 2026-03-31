# frozen_string_literal: true

class CreateGeneratedSignals < ActiveRecord::Migration[8.1]
  def change
    create_table :generated_signals do |t|
      t.references :trading_session, null: false, foreign_key: true
      t.string :symbol, null: false
      t.string :side, null: false
      t.decimal :entry_price, precision: 20, scale: 8, null: false
      t.bigint :candle_timestamp, null: false
      t.string :strategy, null: false
      t.string :source, null: false
      t.string :status, null: false, default: "generated"
      t.string :error_message
      t.jsonb :context, null: false, default: {}
      t.timestamps
    end

    add_index :generated_signals, [:trading_session_id, :created_at]
    add_index :generated_signals, [:symbol, :candle_timestamp]
    add_index :generated_signals, :status
  end
end
