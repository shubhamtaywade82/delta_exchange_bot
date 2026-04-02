# frozen_string_literal: true

FactoryBot.define do
  factory :paper_product_snapshot do
    sequence(:product_id) { |n| 10_000 + n }
    sequence(:symbol) { |n| "SYM#{n}USD" }
    contract_type { "perpetual_futures" }
    contract_value { BigDecimal("0.001") }
    risk_unit_per_contract { BigDecimal("0.001") }
    valuation_strategy { "contract_linear" }
    tick_size { BigDecimal("0.5") }
    mark_price { BigDecimal("50_000") }
    close_price { BigDecimal("49_950") }
    raw_metadata { {} }
  end
end
