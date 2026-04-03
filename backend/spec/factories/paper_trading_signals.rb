# frozen_string_literal: true

FactoryBot.define do
  factory :paper_trading_signal do
    paper_wallet
    product_id { 27 }
    side { "buy" }
    entry_price { BigDecimal("50_000") }
    stop_price { BigDecimal("49_000") }
    max_loss_inr { BigDecimal("50_000") }
    status { "pending" }
    sequence(:idempotency_key) { |n| "sig-#{n}-#{SecureRandom.hex(4)}" }
  end
end
