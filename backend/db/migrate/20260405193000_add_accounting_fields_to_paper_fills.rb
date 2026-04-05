# frozen_string_literal: true

class AddAccountingFieldsToPaperFills < ActiveRecord::Migration[8.1]
  def up
    change_table :paper_fills, bulk: true do |t|
      t.decimal :margin_inr_per_fill, precision: 20, scale: 2
      t.integer :filled_qty
      t.integer :closed_qty, null: false, default: 0
      t.string :liquidity, null: false, default: "taker"
    end

    execute <<~SQL.squish
      UPDATE paper_fills
      SET filled_qty = size,
          margin_inr_per_fill = 0
    SQL

    change_column_null :paper_fills, :filled_qty, false
    change_column_default :paper_fills, :margin_inr_per_fill, from: nil, to: 0
    change_column_null :paper_fills, :margin_inr_per_fill, false
  end

  def down
    change_table :paper_fills, bulk: true do |t|
      t.remove :margin_inr_per_fill
      t.remove :filled_qty
      t.remove :closed_qty
      t.remove :liquidity
    end
  end
end
