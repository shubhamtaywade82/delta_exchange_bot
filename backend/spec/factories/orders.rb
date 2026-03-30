FactoryBot.define do
  factory :order do
    association :trading_session
    symbol { "BTCUSD" }
    side { "buy" }
    size { "1.0" }
    status { "submitted" }
    order_type { "limit_order" }
    price { "50000" }
    sequence(:idempotency_key) { |n| "idem-#{n}" }
    sequence(:client_order_id) { |n| "cid-#{n}" }
  end
end
