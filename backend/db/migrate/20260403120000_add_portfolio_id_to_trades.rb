# frozen_string_literal: true

class AddPortfolioIdToTrades < ActiveRecord::Migration[8.0]
  def change
    add_reference :trades, :portfolio, foreign_key: true, null: true
  end
end
