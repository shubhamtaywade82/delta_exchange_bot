# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::PositionRecalculator do
  let(:session) { create(:trading_session) }
  let(:position) do
    Position.create!(
      symbol: "BTCUSD",
      side: "buy",
      status: "init",
      size: 1,
      needs_reconciliation: true,
      leverage: 10,
      contract_value: 0.001
    )
  end
  let(:order) { create(:order, trading_session: session, position: position, size: 4, status: "submitted") }

  before do
    allow(Trading::Risk::PositionLotSize).to receive(:multiplier_for).and_return(BigDecimal("0.001"))
  end

  it "recomputes quantity and average entry from persisted fills" do
    order
    create(:fill, order: order, quantity: 1, price: 49_000, exchange_fill_id: "F1")
    create(:fill, order: order, quantity: 2, price: 51_000, exchange_fill_id: "F2")

    described_class.call(position.id)

    position.reload
    expect(position.size.to_d).to eq(3.to_d)
    expect(position.entry_price.to_d).to eq((151_000.to_d / 3))
    expect(position.status).to eq("partially_filled")
    expect(position.needs_reconciliation).to eq(false)

    avg = 151_000.to_d / 3
    expected_margin = (3 * BigDecimal("0.001") * avg) / 10
    expect(position.margin.to_d).to eq(expected_margin)
  end
end
