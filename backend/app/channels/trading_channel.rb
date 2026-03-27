# app/channels/trading_channel.rb
class TradingChannel < ApplicationCable::Channel
  def subscribed
    stream_from "trading_channel"
    Rails.logger.info("[TradingChannel] Client subscribed")
  end

  def unsubscribed
    Rails.logger.info("[TradingChannel] Client disconnected")
  end
end
