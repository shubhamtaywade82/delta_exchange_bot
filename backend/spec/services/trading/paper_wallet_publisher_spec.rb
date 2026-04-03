# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::PaperWalletPublisher do
  describe ".wallet_snapshot!" do
    it "returns nil when paper trading is disabled" do
      allow(Trading::PaperTrading).to receive(:enabled?).and_return(false)

      expect(described_class.wallet_snapshot!).to be_nil
    end

    it "returns nil and reports when Redis write fails (portfolio path)" do
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

      redis = instance_double(Redis)
      allow(redis).to receive(:set).and_raise(Redis::BaseError, "connection refused")
      allow(Redis).to receive(:current).and_return(redis)
      allow(Rails.error).to receive(:report)

      expect(described_class.wallet_snapshot!).to be_nil

      expect(Rails.error).to have_received(:report).with(
        instance_of(Redis::BaseError),
        handled: true,
        context: hash_including(
          "component" => "PaperWalletPublisher",
          "operation" => "persist_portfolio_payload"
        )
      )
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
      expect(payload["ledger_margin_exceeds_cash"]).to be(false)
    end

    it "recomputes blocked margin from open positions so stale used_margin does not persist" do
      allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
      allow(Bot::Config).to receive(:load).and_return(
        double("Config", usd_to_inr_rate: 85.0, simulated_capital_inr: 850_000.0)
      )

      session = create(:trading_session, status: "running")
      session.portfolio.update!(
        balance: BigDecimal("117.65"),
        available_balance: BigDecimal("0.77"),
        used_margin: BigDecimal("116.88")
      )

      redis_store = {}
      redis = instance_double(Redis)
      allow(redis).to receive(:set) { |k, v, **| redis_store[k] = v }
      allow(Redis).to receive(:current).and_return(redis)

      payload = described_class.wallet_snapshot!

      expect(payload["blocked_margin_usd"]).to eq(0.0)
      expect(session.portfolio.reload.used_margin).to eq(0)
      expect(session.portfolio.available_balance).to eq(BigDecimal("117.65"))
    end

    it "re-runs PositionRecalculator when summed margin exceeds ledger cash, then re-syncs portfolio" do
      allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
      allow(Bot::Config).to receive(:load).and_return(
        double("Config", usd_to_inr_rate: 85.0, simulated_capital_inr: 850_000.0)
      )

      session = create(:trading_session, status: "running")
      portfolio = session.portfolio
      portfolio.update!(balance: BigDecimal("117.65"), available_balance: BigDecimal("117.65"), used_margin: 0)

      Position.create!(
        portfolio: portfolio,
        symbol: "BTCUSD",
        side: "short",
        status: "filled",
        size: 1,
        entry_price: 66_934,
        leverage: 10,
        margin: BigDecimal("746.38"),
        contract_value: BigDecimal("0.001")
      )

      allow(Redis).to receive(:current).and_return(instance_double(Redis, set: nil))

      expect(Trading::PositionRecalculator).to receive(:call).once do |position_id|
        Position.where(id: position_id).update_all(margin: 5.0)
      end

      payload = described_class.wallet_snapshot!

      expect(payload["blocked_margin_usd"]).to eq(5.0)
      expect(payload["ledger_margin_exceeds_cash"]).to be(false)
      expect(portfolio.reload.available_balance).to eq(BigDecimal("112.65"))
    end

    it "publishes PaperWallet ledger balances to delta:wallet:state when no portfolio session is active" do
      allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
      allow(Bot::Config).to receive(:load).and_return(
        double("Config", usd_to_inr_rate: 85.0, simulated_capital_inr: 850_000.0)
      )
      allow(described_class).to receive(:resolve_paper_portfolio).and_return(nil)

      redis_store = {}
      redis = instance_double(Redis)
      allow(redis).to receive(:set) { |k, v, **| redis_store[k] = v }
      allow(Redis).to receive(:current).and_return(redis)

      wallet = create(:paper_wallet, skip_deposit: true)
      wallet.deposit!(20_000, meta: {})

      payload = described_class.wallet_snapshot!

      expect(payload).to be_a(Hash)
      expect(payload["total_equity_inr"]).to eq(20_000)
      expect(payload["available_inr"]).to eq(20_000)
      expect(payload["capital_inr"]).to eq(20_000)
      expect(payload["cash_balance_inr"]).to eq(20_000)
      expect(payload["ledger_margin_exceeds_cash"]).to be(false)
    end
  end
end
