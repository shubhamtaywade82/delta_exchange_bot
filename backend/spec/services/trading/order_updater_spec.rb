require "rails_helper"

RSpec.describe Trading::OrderUpdater do
  let(:session) { create(:trading_session) }
  let(:position) { Position.create!(portfolio: session.portfolio, symbol: "BTCUSD", side: "buy", status: "init", size: 1) }
  let(:order) do
    create(
      :order,
      trading_session: session,
      position: position,
      status: "created",
      client_order_id: "CID-1",
      exchange_order_id: "EX-1",
      size: 2
    )
  end

  it "updates order lifecycle from exchange status" do
    order
    event = Trading::Events::OrderUpdated.new(
      client_order_id: "CID-1",
      exchange_order_id: "EX-1",
      status: "open"
    )

    described_class.process(event)

    expect(order.reload.status).to eq("submitted")
  end

  it "applies fill quantity when provided in order update" do
    order.update!(status: "submitted")
    event = Trading::Events::OrderUpdated.new(
      client_order_id: "CID-1",
      exchange_order_id: "EX-1",
      status: "partially_filled",
      filled_qty: 1,
      avg_fill_price: 49_850
    )

    described_class.process(event)

    expect(order.reload.status).to eq("partially_filled")
    expect(position.reload.status).to eq("partially_filled")
  end
end
