# frozen_string_literal: true

FactoryBot.define do
  factory :paper_wallet do
    sequence(:name) { |n| "wallet_#{n}" }
    balance_inr { BigDecimal("0") }
    available_inr { BigDecimal("0") }
    used_margin_inr { BigDecimal("0") }
    equity_inr { BigDecimal("0") }
    unrealized_pnl_inr { BigDecimal("0") }
    realized_pnl_inr { BigDecimal("0") }

    transient do
      skip_deposit { false }
      seed_inr { nil }
    end

    after(:create) do |wallet, evaluator|
      next if evaluator.skip_deposit
      next if wallet.paper_wallet_ledger_entries.exists?

      rate = BigDecimal("85")
      inr = evaluator.seed_inr || (BigDecimal("100_000") * rate).round(2)
      wallet.reload
      wallet.deposit!(inr, meta: { "source" => "factory" })
    end
  end
end
