# spec/services/trading/bootstrap/sync_positions_spec.rb
require "rails_helper"

RSpec.describe Trading::Bootstrap::SyncPositions do
  let(:client) { double("DeltaExchange::Client") }

  before do
    allow(client).to receive(:get_positions).and_return([
      { symbol: "BTCUSD", side: "long", size: 1.0, entry_price: 50000.0,
        leverage: 10, margin: 500.0, liquidation_price: 45000.0, product_id: 84 }
    ])
  end

  it "upserts open positions from exchange" do
    expect { described_class.call(client: client) }.to change(Position, :count).by(1)
    position = Position.last
    expect(position.symbol).to eq("BTCUSD")
    expect(position.side).to eq("long")
    expect(position.entry_price).to eq(50000.0)
  end

  it "updates existing open position instead of creating duplicate" do
    Position.create!(symbol: "BTCUSD", side: "long", status: "filled",
                     size: 0.5, entry_price: 48000.0, leverage: 10)
    expect { described_class.call(client: client) }.not_to change(Position, :count)
    expect(Position.find_by(symbol: "BTCUSD").entry_price).to eq(50000.0)
  end

  it "marks local open positions as closed when absent from exchange" do
    stale = Position.create!(symbol: "ETHUSD", side: "long", status: "filled",
                              size: 1.0, entry_price: 3000.0, leverage: 15)
    described_class.call(client: client)
    expect(stale.reload.status).to eq("closed")
  end

  it "does nothing when exchange returns empty positions" do
    allow(client).to receive(:get_positions).and_return([])
    Position.create!(symbol: "BTCUSD", side: "long", status: "filled",
                     size: 1.0, entry_price: 50000.0, leverage: 10)
    described_class.call(client: client)
    expect(Position.find_by(symbol: "BTCUSD").status).to eq("closed")
  end
end
