FactoryBot.define do
  factory :trading_session do
    association :portfolio
    strategy { "multi_timeframe" }
    status { "running" }
    capital { "1000.0" }
    leverage { 10 }
    started_at { Time.current }

    after(:build) do |session|
      next unless session.portfolio

      initial = session.capital.present? && BigDecimal(session.capital.to_s).positive? ? BigDecimal(session.capital.to_s) : BigDecimal("10000")
      session.portfolio.assign_attributes(balance: initial, available_balance: initial, used_margin: 0)
    end
  end
end
