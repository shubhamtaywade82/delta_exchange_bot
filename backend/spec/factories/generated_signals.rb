# frozen_string_literal: true

FactoryBot.define do
  factory :generated_signal do
    trading_session
    symbol { "BTCUSD" }
    side { "buy" }
    entry_price { 100.0 }
    candle_timestamp { Time.current.to_i }
    strategy { "multi_timeframe" }
    source { "mtf" }
    status { "generated" }
    context { {} }
  end
end
