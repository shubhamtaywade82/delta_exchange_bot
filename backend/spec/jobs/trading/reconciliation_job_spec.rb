require "rails_helper"

RSpec.describe Trading::ReconciliationJob, type: :job do
  it "recalculates only dirty positions" do
    dirty = Position.create!(symbol: "BTCUSD", side: "buy", status: "init", size: 1, needs_reconciliation: true)
    clean = Position.create!(symbol: "ETHUSD", side: "buy", status: "init", size: 1, needs_reconciliation: false)

    allow(Trading::PositionRecalculator).to receive(:call)

    described_class.perform_now

    expect(Trading::PositionRecalculator).to have_received(:call).with(dirty.id)
    expect(Trading::PositionRecalculator).not_to have_received(:call).with(clean.id)
  end
end
