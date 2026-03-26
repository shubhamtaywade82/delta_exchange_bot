# app/services/trading/events/tick_received.rb
module Trading
  module Events
    TickReceived = Struct.new(:symbol, :price, :timestamp, :volume, keyword_init: true)
  end
end
