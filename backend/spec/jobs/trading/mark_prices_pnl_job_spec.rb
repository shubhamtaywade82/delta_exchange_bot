# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::MarkPricesPnlJob, type: :job do
  it "updates unrealized_pnl_usd from mark price when present" do
    session = create(:trading_session)
    position = Position.create!(
      portfolio: session.portfolio,
      symbol: "BTCUSD",
      side: "long",
      status: "filled",
      size: 1,
      entry_price: 50_000,
      leverage: 10,
      contract_value: 0.001
    )
    allow(Trading::MarkPrice).to receive(:for_symbol).with("BTCUSD").and_return(51_000.to_d)
    allow(Trading::LiquidationEngine).to receive(:evaluate_and_act!)

    described_class.perform_now

    expect(position.reload.unrealized_pnl_usd.to_f).to be > 0
    expect(Trading::LiquidationEngine).to have_received(:evaluate_and_act!).at_least(:once)
  end
end
