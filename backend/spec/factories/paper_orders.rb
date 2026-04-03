# frozen_string_literal: true

FactoryBot.define do
  factory :paper_order do
    paper_wallet
    paper_product_snapshot
    paper_trading_signal
    side { "buy" }
    order_type { "market_order" }
    size { 10 }
    state { "pending" }
    sequence(:client_order_id) { |n| "paper-co-#{n}-#{SecureRandom.hex(4)}" }
  end
end
