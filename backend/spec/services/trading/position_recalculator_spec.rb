require "rails_helper"

RSpec.describe Trading::PositionRecalculator do
  let(:session) { create(:trading_session) }
  let(:position) { Position.create!(symbol: "BTCUSD", side: "buy", status: "init", size: 1, needs_reconciliation: true) }
  let(:order) { create(:order, trading_session: session, position: position, size: 4, status: "submitted") }

  it "recomputes quantity and average entry from persisted fills" do
    order
    create(:fill, order: order, quantity: 1, price: 49_000, exchange_fill_id: "F1")
    create(:fill, order: order, quantity: 2, price: 51_000, exchange_fill_id: "F2")

    described_class.call(position.id)

    expect(position.reload.size.to_d).to eq(3.to_d)
    expect(position.entry_price.to_d).to eq((151_000.to_d / 3))
    expect(position.status).to eq("partially_filled")
    expect(position.needs_reconciliation).to eq(false)
  end
end
