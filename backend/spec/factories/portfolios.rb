# frozen_string_literal: true

FactoryBot.define do
  factory :portfolio do
    balance { BigDecimal("10000") }
    available_balance { BigDecimal("10000") }
    used_margin { BigDecimal("0") }
  end
end
