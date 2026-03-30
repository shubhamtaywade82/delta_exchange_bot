class AddLiquidationPriceToPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :positions, :liquidation_price, :decimal
  end
end
