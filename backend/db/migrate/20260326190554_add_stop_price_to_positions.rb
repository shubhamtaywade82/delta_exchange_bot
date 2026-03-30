class AddStopPriceToPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :positions, :stop_price, :decimal
  end
end
