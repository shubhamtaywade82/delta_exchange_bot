# frozen_string_literal: true

require "spec_helper"
require "bot/execution/position_tracker"

RSpec.describe Bot::Execution::PositionTracker do
  subject(:tracker) { described_class.new }

  let(:position) do
    {
      symbol: "BTCUSD",
      side: :long,
      lots: 44,
      entry_price: 45_000.0,
      leverage: 10,
      contract_value: 1.0,
      trail_pct: 1.5,
      entry_time: Time.now.utc
    }
  end

  describe "#open" do
    it "records a new position" do
      tracker.open(position)
      expect(tracker.open?("BTCUSD")).to be(true)
    end

    it "sets peak_price and stop_price on open" do
      tracker.open(position)
      pos = tracker.get("BTCUSD")
      expect(pos[:peak_price]).to eq(45_000.0)
      expect(pos[:stop_price]).to eq(45_000.0 * (1 - 0.015))
    end
  end

  describe "#update_trailing_stop" do
    before { tracker.open(position) }

    it "raises peak and stop when price moves in favour (long)" do
      tracker.update_trailing_stop("BTCUSD", 46_000.0)
      pos = tracker.get("BTCUSD")
      expect(pos[:peak_price]).to eq(46_000.0)
      expect(pos[:stop_price]).to be_within(0.01).of(46_000.0 * 0.985)
    end

    it "does not lower peak when price drops (long)" do
      tracker.update_trailing_stop("BTCUSD", 46_000.0)
      tracker.update_trailing_stop("BTCUSD", 44_000.0)
      pos = tracker.get("BTCUSD")
      expect(pos[:peak_price]).to eq(46_000.0)
    end

    it "returns :exit when stop is hit" do
      tracker.update_trailing_stop("BTCUSD", 46_000.0)
      result = tracker.update_trailing_stop("BTCUSD", 45_000.0 * 0.984)
      expect(result).to eq(:exit)
    end

    it "returns nil when stop is not hit" do
      result = tracker.update_trailing_stop("BTCUSD", 45_500.0)
      expect(result).to be_nil
    end
  end

  describe "SHORT position" do
    let(:short_position) do
      {
        symbol:      "ETHUSD",
        side:        :short,
        lots:        10,
        entry_price: 3_000.0,
        leverage:    10,
        contract_value: 1.0,
        trail_pct:   2.0,
        entry_time:  Time.now.utc
      }
    end

    before { tracker.open(short_position) }

    it "sets stop_price above entry on open" do
      pos = tracker.get("ETHUSD")
      expect(pos[:stop_price]).to eq(3_000.0 * (1.0 + 0.02))
    end

    it "lowers peak and raises stop when ltp drops (favourable for short)" do
      tracker.update_trailing_stop("ETHUSD", 2_800.0)
      pos = tracker.get("ETHUSD")
      expect(pos[:peak_price]).to eq(2_800.0)
      expect(pos[:stop_price]).to be_within(0.01).of(2_800.0 * 1.02)
    end

    it "does not raise peak when ltp rises (unfavourable for short)" do
      tracker.update_trailing_stop("ETHUSD", 2_800.0)
      tracker.update_trailing_stop("ETHUSD", 3_100.0)
      pos = tracker.get("ETHUSD")
      expect(pos[:peak_price]).to eq(2_800.0)
    end

    it "returns :exit when ltp rises to or above stop_price" do
      tracker.update_trailing_stop("ETHUSD", 2_800.0)
      result = tracker.update_trailing_stop("ETHUSD", 2_856.0)
      expect(result).to eq(:exit)
    end

    it "returns nil when ltp is below stop_price" do
      result = tracker.update_trailing_stop("ETHUSD", 2_950.0)
      expect(result).to be_nil
    end
  end

  describe "#close" do
    it "removes the position" do
      tracker.open(position)
      tracker.close("BTCUSD")
      expect(tracker.open?("BTCUSD")).to be(false)
    end
  end

  describe "#count" do
    it "returns number of open positions" do
      tracker.open(position)
      expect(tracker.count).to eq(1)
    end
  end

  describe "#all" do
    it "returns a snapshot of all positions" do
      tracker.open(position)
      expect(tracker.all.keys).to include("BTCUSD")
    end
  end
end
