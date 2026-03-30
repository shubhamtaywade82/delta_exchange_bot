class CreateFills < ActiveRecord::Migration[8.1]
  def up
    create_table :fills do |t|
      t.references :order, null: false, foreign_key: true
      t.string :exchange_fill_id, null: false
      t.decimal :quantity, precision: 20, scale: 8, null: false
      t.decimal :price, precision: 20, scale: 8
      t.decimal :fee, precision: 20, scale: 8
      t.datetime :filled_at, null: false
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end

    add_index :fills, :exchange_fill_id, unique: true
    add_index :fills, [:order_id, :filled_at]
  end

  def down
    drop_table :fills
  end
end
