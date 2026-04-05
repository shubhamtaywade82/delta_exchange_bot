# frozen_string_literal: true

class AddLastFundingAtToPaperPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :paper_positions, :last_funding_at, :datetime
    add_index :paper_positions, :last_funding_at
  end
end
