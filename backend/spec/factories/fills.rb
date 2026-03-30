FactoryBot.define do
  factory :fill do
    association :order
    sequence(:exchange_fill_id) { |n| "fill-#{n}" }
    quantity { "1.0" }
    price { "50000.0" }
    fee { "5.0" }
    filled_at { Time.current }
    raw_payload { {} }
  end
end
