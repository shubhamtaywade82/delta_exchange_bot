require "rails_helper"

RSpec.describe Trading::FillProcessor do
  let(:session) { create(:trading_session) }
  let(:position) { Position.create!(symbol: "BTCUSD", side: "buy", status: "init", size: 1) }
  let(:order) do
    create(
      :order,
      trading_session: session,
      position: position,
      symbol: "BTCUSD",
      side: "buy",
      size: 2,
      status: "submitted",
      exchange_order_id: "EX-1"
    )
  end

  it "persists unique fill and derives order/position state" do
    order
    event = Trading::Events::OrderFilled.new(
      exchange_fill_id: "F-1",
      exchange_order_id: "EX-1",
      quantity: 1,
      price: 49_900,
      fee: 2,
      filled_at: Time.current,
      status: "open",
      raw_payload: { source: "spec" }
    )

    described_class.process(event)

    expect(Fill.find_by(exchange_fill_id: "F-1")).to be_present
    expect(order.reload.status).to eq("partially_filled")
    expect(position.reload.status).to eq("partially_filled")
    expect(position.size.to_d).to eq(1.to_d)
    expect(position.needs_reconciliation).to eq(false)
  end

  it "skips side effects for duplicate fill id" do
    order
    create(:fill, order: order, exchange_fill_id: "F-1", quantity: 1, price: 49_900)

    allow(Trading::PositionRecalculator).to receive(:call)

    event = Trading::Events::OrderFilled.new(
      exchange_fill_id: "F-1",
      exchange_order_id: "EX-1",
      quantity: 1,
      price: 49_900,
      fee: 2,
      filled_at: Time.current,
      status: "open",
      raw_payload: { source: "spec" }
    )

    expect { described_class.process(event) }.not_to change(Fill, :count)
    expect(Trading::PositionRecalculator).not_to have_received(:call)
  end
end
