# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::SmcSessionRanges do
  describe ".active_sessions" do
    it "maps Asia to 00:00–07:59 UTC" do
      expect(described_class.active_sessions(0)).to eq(%w[asian])
      expect(described_class.active_sessions(7)).to eq(%w[asian])
    end

    it "maps London-only hours before New York opens" do
      expect(described_class.active_sessions(8)).to eq(%w[london])
      expect(described_class.active_sessions(12)).to eq(%w[london])
    end

    it "includes both London and New York during overlap 13:00–15:59 UTC" do
      expect(described_class.active_sessions(13)).to eq(%w[london new_york])
      expect(described_class.active_sessions(14)).to eq(%w[london new_york])
      expect(described_class.active_sessions(15)).to eq(%w[london new_york])
    end

    it "maps New York alone when London session has ended" do
      expect(described_class.active_sessions(16)).to eq(%w[new_york])
      expect(described_class.active_sessions(20)).to eq(%w[new_york])
    end

    it "uses after_hours when no major session matches" do
      expect(described_class.active_sessions(21)).to eq(%w[after_hours])
      expect(described_class.active_sessions(23)).to eq(%w[after_hours])
    end
  end

  describe ".snapshot" do
    def candle(utc_time, high:, low:)
      t = Time.zone.parse(utc_time).utc
      { timestamp: t.to_i, high: high, low: low, open: low, close: (high + low) / 2.0 }
    end

    it "aggregates highs and lows into every active session for each candle" do
      candles = [
        candle("2024-06-01 14:00:00", high: 110.0, low: 100.0),
        candle("2024-06-01 14:30:00", high: 120.0, low: 105.0)
      ]
      snap = described_class.snapshot(candles)

      expect(snap["london"]).to eq("high" => 120.0, "low" => 100.0)
      expect(snap["new_york"]).to eq("high" => 120.0, "low" => 100.0)
    end

    it "keeps Asian range separate from London" do
      candles = [
        candle("2024-06-01 05:00:00", high: 50.0, low: 40.0),
        candle("2024-06-01 10:00:00", high: 60.0, low: 55.0)
      ]
      snap = described_class.snapshot(candles)

      expect(snap["asian"]).to eq("high" => 50.0, "low" => 40.0)
      expect(snap["london"]).to eq("high" => 60.0, "low" => 55.0)
    end
  end
end
