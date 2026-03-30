FactoryBot.define do
  factory :trading_session do
    strategy { "multi_timeframe" }
    status { "running" }
    capital { "1000.0" }
    leverage { 10 }
    started_at { Time.current }
  end
end
