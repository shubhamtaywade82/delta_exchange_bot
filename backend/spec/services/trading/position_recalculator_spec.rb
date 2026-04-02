# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::PositionRecalculator do
  let(:session) { create(:trading_session) }
  let(:position) do
    Position.create!(
      portfolio: session.portfolio,
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

  it "retries once when position update hits a serialization conflict" do
    order
    create(:fill, order: order, quantity: 1, price: 49_000, exchange_fill_id: "F1")

    attempts = 0
    allow_any_instance_of(Position).to receive(:update!).and_wrap_original do |original, *args, **kwargs|
      attempts += 1
      raise ActiveRecord::SerializationFailure, "concurrent update" if attempts == 1

      original.call(*args, **kwargs)
    end

    described_class.call(position.id)

    expect(attempts).to eq(2)
    expect(position.reload.size.to_d).to eq(1.to_d)
  end

  it "sets trail_pct peak_price and stop_price when net position opens without trail" do
    config = instance_double(Bot::Config, trailing_stop_pct: 1.0)
    allow(Bot::Config).to receive(:load).and_return(config)

    order.update!(size: 1)
    create(:fill, order: order, quantity: 1, price: 50_000, exchange_fill_id: "Ftrail")

    described_class.call(position.id)

    position.reload
    expect(position.trail_pct).to eq(BigDecimal("1"))
    expect(position.peak_price).to eq(position.entry_price)
    expect(position.stop_price).to eq(position.entry_price.to_d * BigDecimal("0.99"))
  end

  it "recomputes quantity and average entry from persisted fills" do
    order
    create(:fill, order: order, quantity: 1, price: 49_000, exchange_fill_id: "F1")
    create(:fill, order: order, quantity: 2, price: 51_000, exchange_fill_id: "F2")

    described_class.call(position.id)

    position.reload
    expect(position.size.to_d).to eq(3.to_d)
    avg = (151_000.to_d / 3).round(Trading::PositionRecalculator::AVG_ENTRY_DECIMALS)
    expect(position.entry_price.to_d).to eq(avg)
    expect(position.status).to eq("partially_filled")
    expect(position.needs_reconciliation).to eq(false)

    expected_margin = (3 * BigDecimal("0.001") * avg) / 10
    expect(position.margin.to_d).to eq(expected_margin)
  end
end
