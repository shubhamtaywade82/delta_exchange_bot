class AddExecutionConstraints < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :fills, "quantity > 0", name: "fills_quantity_positive"
    add_check_constraint :fills, "price IS NULL OR price > 0", name: "fills_price_positive"
    add_check_constraint :orders,
      "filled_qty IS NULL OR size IS NULL OR filled_qty <= size",
      name: "orders_no_overfill"
  end

  def down
    remove_check_constraint :orders, name: "orders_no_overfill"
    remove_check_constraint :fills, name: "fills_price_positive"
    remove_check_constraint :fills, name: "fills_quantity_positive"
  end
end
