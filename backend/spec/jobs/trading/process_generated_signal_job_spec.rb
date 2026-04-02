# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::ProcessGeneratedSignalJob, type: :job do
  include ActiveJob::TestHelper

  let(:session) { create(:trading_session, status: "running") }
  let(:signal) do
    create(
      :generated_signal,
      trading_session: session,
      status: "generated",
      symbol: "BTCUSD",
      side: "buy",
      entry_price: 100,
      candle_timestamp: Time.current.to_i
    )
  end

  let(:valid_allocation) do
    instance_double(Trading::Paper::Allocation, valid?: true)
  end

  before do
    create(:symbol_config, symbol: "BTCUSD", enabled: true, metadata: { "contract_lot_multiplier" => "1" })
    allow(Trading::RunnerClient).to receive(:build).and_return(double("client"))
    allow(Trading::ExecutionEngine).to receive(:execute)
    allow(Trading::IdempotencyGuard).to receive(:acquire).and_return(true)
    allow(Trading::IdempotencyGuard).to receive(:release)
    allow(Trading::Paper::SignalPreflight).to receive(:call).and_return(valid_allocation)
  end

  it "executes engine and marks signal executed when preflight passes" do
    described_class.perform_now(signal.id)

    expect(Trading::ExecutionEngine).to have_received(:execute).once
    expect(signal.reload.status).to eq("executed")
  end

  it "rejects when preflight allocation is invalid" do
    allow(Trading::Paper::SignalPreflight).to receive(:call)
      .and_return(instance_double(Trading::Paper::Allocation, valid?: false))

    described_class.perform_now(signal.id)

    expect(Trading::ExecutionEngine).not_to have_received(:execute)
    expect(signal.reload.status).to eq("rejected")
  end
end
