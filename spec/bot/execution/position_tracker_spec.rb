# frozen_string_literal: true

require "spec_helper"
require "bot/execution/position_tracker"

RSpec.describe Bot::Execution::PositionTracker do
  subject(:tracker) { described_class.new }

  let(:position) do
    {
      symbol: "BTCUSDT",
      side: :long,
      lots: 44,
      entry_price: 45_000.0,
      leverage: 10,
      trail_pct: 1.5,
      entry_time: Time.now.utc
    }
  end

  describe "#open" do
    it "records a new position" do
      tracker.open(position)
      expect(tracker.open?("BTCUSDT")).to be(true)
    end

    it "sets peak_price and stop_price on open" do
      tracker.open(position)
      pos = tracker.get("BTCUSDT")
      expect(pos[:peak_price]).to eq(45_000.0)
      expect(pos[:stop_price]).to eq(45_000.0 * (1 - 0.015))
    end
  end

  describe "#update_trailing_stop" do
    before { tracker.open(position) }

    it "raises peak and stop when price moves in favour (long)" do
      tracker.update_trailing_stop("BTCUSDT", 46_000.0)
      pos = tracker.get("BTCUSDT")
      expect(pos[:peak_price]).to eq(46_000.0)
      expect(pos[:stop_price]).to be_within(0.01).of(46_000.0 * 0.985)
    end

    it "does not lower peak when price drops (long)" do
      tracker.update_trailing_stop("BTCUSDT", 46_000.0)
      tracker.update_trailing_stop("BTCUSDT", 44_000.0)
      pos = tracker.get("BTCUSDT")
      expect(pos[:peak_price]).to eq(46_000.0)
    end

    it "returns :exit when stop is hit" do
      tracker.update_trailing_stop("BTCUSDT", 46_000.0)
      result = tracker.update_trailing_stop("BTCUSDT", 45_000.0 * 0.984)
      expect(result).to eq(:exit)
    end

    it "returns nil when stop is not hit" do
      result = tracker.update_trailing_stop("BTCUSDT", 45_500.0)
      expect(result).to be_nil
    end
  end

  describe "#close" do
    it "removes the position" do
      tracker.open(position)
      tracker.close("BTCUSDT")
      expect(tracker.open?("BTCUSDT")).to be(false)
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
      expect(tracker.all.keys).to include("BTCUSDT")
    end
  end
end
