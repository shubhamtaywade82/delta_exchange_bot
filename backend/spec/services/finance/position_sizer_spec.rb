# frozen_string_literal: true

require "rails_helper"

RSpec.describe Finance::PositionSizer do
  describe ".compute!" do
    it "sizes ETHUSD example: ~1176 USD, 0.5% risk, entry 3000, stop 2950, cv 0.01 → 11 contracts" do
      balance_usd = 100_000.0 / 85.0
      # risk 0.5% ≈ 5.88 USD; stop_distance 50; risk_per_contract = 50 × 0.01 = 0.5
      # contracts = floor(5.88 / 0.5) = 11

      result = described_class.compute!(
        balance_usd: balance_usd,
        risk_percent: 0.005,
        entry_price: 3000.0,
        stop_price: 2950.0,
        contract_value: 0.01
      )

      expect(result.final_contracts).to eq(11)
      expect(result.contracts).to eq(11)
      expect(result.qty_risk).to eq(11)
      expect(result.qty_margin).to eq(described_class::NO_MARGIN_CAP)
      expect(result.stop_distance).to eq(50.0)
      expect(result.risk_per_contract).to be_within(1e-9).of(0.5)
    end

    it "caps by margin when leverage and margin_wallet bind before risk" do
      balance_usd = 100_000.0 / 85.0
      result = described_class.compute!(
        balance_usd: balance_usd,
        risk_percent: 0.05,
        entry_price: 60_000.0,
        stop_price: 59_500.0,
        contract_value: 0.001,
        leverage: 1,
        margin_wallet_usd: 200.0
      )

      expect(result.qty_risk).to eq(117)
      expect(result.qty_margin).to eq(3)
      expect(result.final_contracts).to eq(3)
      expect(result.contracts).to eq(3)
    end

    it "caps by position_size_limit when lower than risk and margin" do
      balance_usd = 100_000.0 / 85.0
      result = described_class.compute!(
        balance_usd: balance_usd,
        risk_percent: 0.05,
        entry_price: 60_000.0,
        stop_price: 59_500.0,
        contract_value: 0.001,
        leverage: 100,
        position_size_limit: 5
      )

      expect(result.qty_risk).to eq(117)
      expect(result.final_contracts).to eq(5)
    end

    it "uses margin_wallet_usd when passed; otherwise uses balance_usd for margin cap" do
      balance_usd = 500.0
      without_extra = described_class.compute!(
        balance_usd: balance_usd,
        risk_percent: 0.01,
        entry_price: 100.0,
        stop_price: 99.0,
        contract_value: 1.0,
        leverage: 10
      )
      wallet_usd = 80.0
      qty_margin_expected = ((wallet_usd * 0.98 * 10) / (1.0 * 100.0)).floor

      with_wallet = described_class.compute!(
        balance_usd: balance_usd,
        risk_percent: 0.01,
        entry_price: 100.0,
        stop_price: 99.0,
        contract_value: 1.0,
        leverage: 10,
        margin_wallet_usd: wallet_usd
      )

      expect(with_wallet.qty_margin).to eq(qty_margin_expected)
      expect(without_extra.qty_margin).to be > with_wallet.qty_margin
    end

    it "raises when stop distance is zero" do
      expect {
        described_class.compute!(
          balance_usd: 10_000,
          risk_percent: 0.01,
          entry_price: 100.0,
          stop_price: 100.0,
          contract_value: 0.01
        )
      }.to raise_error(ArgumentError, /stop distance/)
    end

    it "raises when fee_buffer is out of range" do
      expect {
        described_class.compute!(
          balance_usd: 10_000,
          risk_percent: 0.01,
          entry_price: 100.0,
          stop_price: 90.0,
          contract_value: 0.01,
          leverage: 10,
          fee_buffer: 1.5
        )
      }.to raise_error(ArgumentError, /fee_buffer/)
    end
  end
end
