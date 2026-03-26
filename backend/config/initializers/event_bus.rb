# frozen_string_literal: true

# Wire global EventBus subscriptions at boot.
# These run independently of any session — they broadcast to the frontend
# for all events regardless of which session produced them.
Rails.application.config.after_initialize do
  Trading::EventBus.subscribe(:position_updated) do |event|
    ActionCable.server.broadcast("trading_channel", {
      type:    "position_updated",
      symbol:  event.symbol,
      status:  event.status,
      pnl:     event.unrealized_pnl
    })
  end

  Trading::EventBus.subscribe(:tick_received) do |event|
    ActionCable.server.broadcast("trading_channel", {
      type:   "ltp",
      symbol: event.symbol,
      price:  event.price
    })
  end
end
