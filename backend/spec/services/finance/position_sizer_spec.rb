# frozen_string_literal: true

require "rails_helper"

RSpec.describe Finance::PositionSizer do
  describe ".compute!" do
    it "sizes ETHUSD example: ₹100k, 0.5% risk, entry 3000, stop 2950, cv 0.01 → 11 contracts" do
      balance_inr = 100_000.0
      # 100_000 / 85 ≈ 1176.47 USD; risk 0.5% ≈ 5.88 USD
      # stop_distance 50; risk_per_contract = 50 × 0.01 = 0.5
      # contracts = floor(5.88 / 0.5) = 11

      result = described_class.compute!(
        balance_inr: balance_inr,
        risk_percent: 0.005,
        entry_price: 3000.0,
        stop_price: 2950.0,
        contract_value: 0.01,
        usd_inr: 85.0
      )

      expect(result.contracts).to eq(11)
      expect(result.stop_distance).to eq(50.0)
      expect(result.risk_per_contract).to be_within(1e-9).of(0.5)
    end

    it "raises when stop distance is zero" do
      expect {
        described_class.compute!(
          balance_inr: 10_000,
          risk_percent: 0.01,
          entry_price: 100.0,
          stop_price: 100.0,
          contract_value: 0.01,
          usd_inr: 85.0
        )
      }.to raise_error(ArgumentError, /stop distance/)
    end
  end
end
