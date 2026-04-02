# frozen_string_literal: true

FactoryBot.define do
  factory :portfolio do
    balance { BigDecimal("20000") }
    available_balance { BigDecimal("20000") }
    used_margin { BigDecimal("0") }
  end
end
