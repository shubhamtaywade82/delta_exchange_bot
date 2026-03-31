# app/services/trading/events/signal_generated.rb
module Trading
  module Events
    SignalGenerated = Struct.new(:symbol, :side, :entry_price, :candle_timestamp,
                                 :strategy, :session_id, :stop_price, keyword_init: true)
  end
end
