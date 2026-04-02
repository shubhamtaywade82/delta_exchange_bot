# frozen_string_literal: true

class AddStopAndRiskToGeneratedSignals < ActiveRecord::Migration[8.1]
  def change
    change_table :generated_signals, bulk: true do |t|
      t.decimal :stop_price, precision: 24, scale: 8
      t.decimal :risk_pct, precision: 8, scale: 6
    end
  end
end
