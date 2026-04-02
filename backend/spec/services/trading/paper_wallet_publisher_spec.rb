# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::PaperWalletPublisher do
  describe ".wallet_snapshot!" do
    it "returns nil when paper trading is disabled" do
      allow(Trading::PaperTrading).to receive(:enabled?).and_return(false)

      expect(described_class.wallet_snapshot!).to be_nil
    end

    it "aligns spendable with equity when no active positions (no stale blocked margin)" do
      allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
      allow(Bot::Config).to receive(:load).and_return(
        double("Config", usd_to_inr_rate: 85.0, simulated_capital_inr: 850_000.0)
      )

      session = create(:trading_session, status: "running")
      session.portfolio.update!(
        balance: BigDecimal("10000"),
        available_balance: BigDecimal("10000"),
        used_margin: 0
      )

      redis_store = {}
      redis = instance_double(Redis)
      allow(redis).to receive(:set) { |k, v, **| redis_store[k] = v }
      allow(Redis).to receive(:current).and_return(redis)

      payload = described_class.wallet_snapshot!

      expect(payload).to be_a(Hash)
      expect(payload["blocked_margin_usd"]).to eq(0.0)
      expect(payload["cash_balance_usd"]).to eq(10_000.0)
      expect(payload["unrealized_pnl_usd"]).to eq(0.0)
      expect(payload["available_usd"]).to eq(payload["total_equity_usd"])
      expect(payload["available_inr"]).to eq(payload["total_equity_inr"])
    end
  end
end
