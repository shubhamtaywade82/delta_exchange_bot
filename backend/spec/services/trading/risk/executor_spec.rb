# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Risk::Executor do
  describe ".tighten_sl!" do
    let(:portfolio) { create(:portfolio) }

    it "places the stop below the mark for a long" do
      position = create(
        :position,
        portfolio: portfolio,
        symbol: "BTCUSD",
        side: "long",
        status: "filled",
        size: 1.0,
        entry_price: 50_000.0,
        stop_price: 49_000.0
      )

      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("RISK_DANGER_STOP_BUFFER", "0.98").and_return("0.98")

      described_class.tighten_sl!(position, mark_price: 100_000.0)

      position.reload
      expect(position.stop_price.to_d).to eq(BigDecimal("98000"))
    end

    it "places the stop above the mark for a short" do
      position = create(
        :position,
        portfolio: portfolio,
        symbol: "BTCUSD",
        side: "short",
        status: "filled",
        size: 1.0,
        entry_price: 100_000.0,
        stop_price: 101_000.0
      )

      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("RISK_DANGER_STOP_BUFFER", "0.98").and_return("0.98")

      described_class.tighten_sl!(position, mark_price: 100_000.0)

      position.reload
      expected = (BigDecimal("100000") / BigDecimal("0.98")).round(8)
      expect(position.stop_price.to_d).to eq(expected)
      expect(position.stop_price.to_f).to be > 100_000.0
    end
  end
end
