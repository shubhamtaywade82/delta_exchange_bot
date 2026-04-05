# frozen_string_literal: true

class AddPositionIdToTrades < ActiveRecord::Migration[8.1]
  def change
    add_reference :trades, :position, null: true, foreign_key: true, index: false
    add_index :trades, :position_id,
              unique: true,
              where: "position_id IS NOT NULL",
              name: "index_trades_unique_position_id_when_present"
  end
end
