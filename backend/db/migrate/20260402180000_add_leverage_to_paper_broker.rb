# frozen_string_literal: true

class AddLeverageToPaperBroker < ActiveRecord::Migration[8.1]
  def change
    add_column :paper_product_snapshots, :default_leverage, :integer

    add_column :paper_positions, :leverage, :integer, null: false, default: 1
  end
end
