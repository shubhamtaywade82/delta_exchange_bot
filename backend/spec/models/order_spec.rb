# spec/models/order_spec.rb
require "rails_helper"

RSpec.describe Order, type: :model do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }

  it "is valid with required attributes" do
    order = Order.new(
      trading_session: session,
      symbol: "BTCUSD",
      side: "buy",
      size: 1.0,
      price: 50000.0,
      order_type: "limit_order",
      status: "pending",
      idempotency_key: "delta:order:BTCUSD:buy:1711440000"
    )
    expect(order).to be_valid
  end

  it "is invalid without idempotency_key" do
    order = Order.new(symbol: "BTCUSD", side: "buy", size: 1.0, status: "pending")
    expect(order).not_to be_valid
  end

  it "enforces unique idempotency_key" do
    attrs = { trading_session: session, symbol: "BTCUSD", side: "buy", size: 1.0,
              price: 50000.0, order_type: "limit_order", status: "pending",
              idempotency_key: "unique-key-123" }
    Order.create!(attrs)
    duplicate = Order.new(attrs)
    expect(duplicate).not_to be_valid
  end

  it "#filled? returns true when status is filled" do
    expect(Order.new(status: "filled")).to be_filled
  end

  it "#open? returns true when status is open or partially_filled" do
    expect(Order.new(status: "open")).to be_open
    expect(Order.new(status: "partially_filled")).to be_open
  end
end
