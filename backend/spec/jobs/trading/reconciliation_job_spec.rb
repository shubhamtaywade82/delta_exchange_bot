require "rails_helper"

RSpec.describe Trading::ReconciliationJob, type: :job do
  it "recalculates only dirty positions" do
    pf = create(:portfolio)
    dirty = Position.create!(portfolio: pf, symbol: "BTCUSD", side: "buy", status: "init", size: 1, needs_reconciliation: true)
    clean = Position.create!(portfolio: pf, symbol: "ETHUSD", side: "buy", status: "init", size: 1, needs_reconciliation: false)

    allow(Trading::PositionRecalculator).to receive(:call)

    described_class.perform_now

    expect(Trading::PositionRecalculator).to have_received(:call).with(dirty.id)
    expect(Trading::PositionRecalculator).not_to have_received(:call).with(clean.id)
  end

  it "recalculates all active positions when POSITION_RECONCILE_ALL_ACTIVE is set" do
    create(:portfolio)

    allow(Trading::PositionReconciliation).to receive(:recalculate_all_active!).and_return(2)
    old = ENV.fetch("POSITION_RECONCILE_ALL_ACTIVE", nil)
    ENV["POSITION_RECONCILE_ALL_ACTIVE"] = "true"
    described_class.perform_now
    expect(Trading::PositionReconciliation).to have_received(:recalculate_all_active!)
  ensure
    old.nil? ? ENV.delete("POSITION_RECONCILE_ALL_ACTIVE") : ENV["POSITION_RECONCILE_ALL_ACTIVE"] = old
  end
end
