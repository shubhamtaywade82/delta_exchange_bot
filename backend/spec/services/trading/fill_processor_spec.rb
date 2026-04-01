require "rails_helper"

RSpec.describe Trading::FillProcessor do
  let(:session) { create(:trading_session) }
  let(:position) do
    Position.create!(
      portfolio: session.portfolio,
      symbol: "BTCUSD",
      side: "buy",
      status: "init",
      size: 1,
      leverage: 10
    )
  end

  before do
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(false)
    allow(Trading::Risk::PositionLotSize).to receive(:multiplier_for).and_return(BigDecimal("0.001"))
  end
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

  it "publishes paper wallet snapshot when paper trading is enabled" do
    order
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
    allow(Trading::PaperWalletPublisher).to receive(:publish!)

    event = Trading::Events::OrderFilled.new(
      exchange_fill_id: "F-paper",
      exchange_order_id: "EX-1",
      quantity: 1,
      price: 49_900,
      fee: 0,
      filled_at: Time.current,
      status: "open",
      raw_payload: { source: "spec" }
    )

    described_class.process(event)

    expect(Trading::PaperWalletPublisher).to have_received(:publish!)
  end

  it "raises OverfillError when cumulative fills would exceed order size" do
    order
    create(:fill, order: order, exchange_fill_id: "F-partial", quantity: 2, price: 49_900)

    event = Trading::Events::OrderFilled.new(
      exchange_fill_id: "F-overflow",
      exchange_order_id: "EX-1",
      quantity: 1,
      price: 49_900,
      fee: 0,
      filled_at: Time.current,
      status: "open",
      raw_payload: { source: "spec" }
    )

    expect {
      described_class.process(event)
    }.to raise_error(Trading::FillProcessor::OverfillError, /Overfill/)
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
