FactoryBot.define do
  factory :trade do
    symbol { "MyString" }
    side { "MyString" }
    entry_price { "9.99" }
    exit_price { "9.99" }
    size { "9.99" }
    pnl_usd { "9.99" }
    pnl_inr { "9.99" }
    duration_seconds { 1 }
    closed_at { "2026-03-26 15:46:41" }
  end
end
