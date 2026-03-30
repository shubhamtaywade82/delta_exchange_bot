# frozen_string_literal: true

module Trading
  module Events
    OrderUpdated = Struct.new(
      :client_order_id,
      :exchange_order_id,
      :status,
      :filled_qty,
      :avg_fill_price,
      :raw_payload,
      keyword_init: true
    )
  end
end
