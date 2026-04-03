# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Handlers::PositionHandler do
  let(:event) do
    Trading::Events::PositionUpdated.new(
      symbol: "BTCUSD",
      side: "long",
      size: 1.0,
      entry_price: 50_000.0,
      mark_price: 50_100.0,
      unrealized_pnl: 10.0,
      status: "filled"
    )
  end

  it "broadcasts the position payload" do
    allow(ActionCable.server).to receive(:broadcast)

    described_class.new(event).call

    expect(ActionCable.server).to have_received(:broadcast).with(
      "trading_channel",
      hash_including(type: "position_updated", symbol: "BTCUSD")
    )
  end

  it "swallows broadcast failures and reports them" do
    allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "cable unavailable")
    allow(Rails.logger).to receive(:error)
    allow(Rails.error).to receive(:report)

    expect { described_class.new(event).call }.not_to raise_error

    expect(Rails.error).to have_received(:report).with(
      an_object_having_attributes(message: "cable unavailable"),
      handled: true,
      context: hash_including("component" => "PositionHandler", "symbol" => "BTCUSD")
    )
  end
end
