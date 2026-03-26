# app/services/trading/events/order_filled.rb
module Trading
  module Events
    OrderFilled = Struct.new(:exchange_order_id, :symbol, :side, :filled_qty,
                              :avg_fill_price, :status, keyword_init: true)
  end
end
