# frozen_string_literal: true

module Trading
  module Events
    OrderFilled = Struct.new(
      :exchange_fill_id,
      :exchange_order_id,
      :client_order_id,
      :symbol,
      :side,
      :quantity,
      :price,
      :fee,
      :filled_at,
      :status,
      :raw_payload,
      keyword_init: true
    )
  end
end
