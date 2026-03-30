# Wire global EventBus subscriptions for broadcast to frontend.

Rails.application.config.after_initialize do
  # Broadcast tick LTP to frontend
  Trading::EventBus.subscribe(:tick_received) do |event|
    ActionCable.server.broadcast("trading_channel", {
      type:   "ltp",
      symbol: event.symbol,
      price:  event.price
    })
  end

  # Broadcast position updates
  Trading::EventBus.subscribe(:position_updated) do |event|
    ActionCable.server.broadcast("trading_channel", {
      type:    "position_updated",
      symbol:  event.symbol,
      side:    event.side,
      status:  event.status,
      size:    event.size,
      pnl:     event.unrealized_pnl
    })
  end
end
