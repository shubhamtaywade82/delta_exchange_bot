# frozen_string_literal: true

FactoryBot.define do
  factory :paper_wallet do
    sequence(:name) { |n| "wallet_#{n}" }
    cash_balance { BigDecimal("100_000") }
    realized_pnl { BigDecimal("0") }
    unrealized_pnl { BigDecimal("0") }
    equity { BigDecimal("100_000") }
    reserved_margin { BigDecimal("0") }
  end
end
