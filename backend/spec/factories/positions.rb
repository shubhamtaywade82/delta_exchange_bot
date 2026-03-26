FactoryBot.define do
  factory :position do
    symbol { "MyString" }
    side { "MyString" }
    status { "MyString" }
    entry_price { "9.99" }
    exit_price { "9.99" }
    size { "9.99" }
    leverage { 1 }
    margin { "9.99" }
    pnl_usd { "9.99" }
    pnl_inr { "9.99" }
    entry_time { "2026-03-26 15:46:40" }
    exit_time { "2026-03-26 15:46:40" }
    product_id { 1 }
    peak_price { "9.99" }
    trail_pct { "9.99" }
  end
end
