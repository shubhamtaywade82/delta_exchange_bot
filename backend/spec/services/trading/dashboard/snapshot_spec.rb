# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Dashboard::Snapshot do
  describe ".call" do
    around do |example|
      previous_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = previous_cache
    end

    before do
      allow(Bot::Execution::IncidentStore).to receive(:latest).and_return(nil)
      allow(Bot::Execution::IncidentStore).to receive(:recent).and_return([])
      SymbolConfig.create!(symbol: "BTCUSD", leverage: 10, enabled: true)
    end

    context "when paper trading with a running session" do
      before do
        allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)
        allow(Trading::PaperWalletPublisher).to receive(:wallet_snapshot!).and_return(
          "total_equity_usd" => 150.0,
          "total_equity_inr" => 12_750,
          "cash_balance_usd" => 150.0,
          "cash_balance_inr" => 12_750,
          "unrealized_pnl_usd" => 0.0,
          "unrealized_pnl_inr" => 0,
          "available_usd" => 150.0,
          "available_inr" => 12_750,
          "blocked_margin_usd" => 0.0,
          "blocked_margin_inr" => 0,
          "paper_mode" => true,
          "updated_at" => Time.current.iso8601,
          "stale" => false
        )
      end

      it "does not fold unrelated Trade rows into TOTAL_PNL" do
        session = create(:trading_session, status: "running")
        create(:trade, pnl_usd: -50_000, closed_at: 1.day.ago)

        payload = described_class.call(calendar_day: nil, trades_day: nil, trades_limit: nil)

        expect(payload[:stats][:total_pnl_usd]).to eq(0.0)
        expect(TradingSession.where(status: "running").count).to eq(1)
        expect(session.portfolio_id).to be_present
      end

      it "falls back to today settled trades for TOTAL_PNL and KPIs when no rows match the session portfolio" do
        session = create(:trading_session, status: "running", capital: "1000.0")
        other = create(:portfolio)
        create(
          :trade,
          portfolio: other,
          symbol: "BTCUSD",
          side: "short",
          pnl_usd: 12.0,
          closed_at: Time.current,
          strategy: "multi_timeframe",
          regime: "trending"
        )

        payload = described_class.call(calendar_day: nil, trades_day: nil, trades_limit: nil)

        expect(session.portfolio_id).to be_present
        expect(payload[:stats][:total_pnl_usd]).to eq(12.0)
        expect(payload[:stats][:win_rate]).to eq(100.0)
      end

      it "keeps WIN_RATE on the same broker-settled session scope as TOTAL_PNL" do
        session = create(:trading_session, status: "running")
        create(:trade, pnl_usd: -100.0, closed_at: 1.day.ago)
        create(
          :trade,
          portfolio: session.portfolio,
          symbol: "BTCUSD",
          side: "short",
          pnl_usd: 10.0,
          closed_at: Time.current,
          strategy: "multi_timeframe",
          regime: "trending"
        )
        create(
          :trade,
          portfolio: session.portfolio,
          symbol: "ETHUSD",
          side: "short",
          pnl_usd: 5.0,
          closed_at: Time.current,
          strategy: "multi_timeframe",
          regime: "trending"
        )

        payload = described_class.call(calendar_day: nil, trades_day: nil, trades_limit: nil)

        expect(payload[:stats][:total_pnl_usd]).to eq(15.0)
        expect(payload[:stats][:win_rate]).to eq(100.0)
      end

      it "scopes open positions to the running session portfolio" do
        session = create(:trading_session, status: "running")
        other = create(:portfolio)
        create(
          :position,
          portfolio: other,
          symbol: "BTCUSD",
          status: "filled",
          side: "long",
          size: 1,
          entry_price: 50_000,
          margin: 100,
          unrealized_pnl_usd: 0
        )

        payload = described_class.call(calendar_day: nil, trades_day: nil, trades_limit: nil)

        expect(payload[:positions]).to eq([])
        expect(payload[:positions_meta][:count]).to eq(0)
      end

      it "includes realized PnL from the portfolio ledger, not the trades table" do
        session = create(:trading_session, status: "running")
        create(:trade, pnl_usd: -10_000, closed_at: 1.day.ago)

        order = create(:order, portfolio: session.portfolio, trading_session: session, symbol: "BTCUSD")
        fill = create(:fill, order: order)
        PortfolioLedgerEntry.create!(
          portfolio: session.portfolio,
          fill: fill,
          realized_pnl_delta: -2.5,
          balance_delta: -2.5
        )

        payload = described_class.call(calendar_day: nil, trades_day: nil, trades_limit: nil)

        expect(payload[:stats][:total_pnl_usd]).to eq(-2.5)
      end

      it "uses portfolio cash vs session seed when the ledger is empty (synthetic paper exits)" do
        session = create(:trading_session, status: "running", capital: "1000.0")
        session.portfolio.update!(balance: 1042.75, available_balance: 1042.75, used_margin: 0)
        create(:trade, pnl_usd: 50, closed_at: 1.day.ago)

        payload = described_class.call(calendar_day: nil, trades_day: nil, trades_limit: nil)

        expect(payload[:stats][:total_pnl_usd]).to eq(42.75)
      end

      it "sums broker-settled trades for the session portfolio when the ledger is empty and balance never moved" do
        session = create(:trading_session, status: "running", capital: "1000.0")
        create(
          :trade,
          portfolio: session.portfolio,
          symbol: "BTCUSD",
          side: "short",
          pnl_usd: 34.38,
          closed_at: Time.current,
          strategy: "multi_timeframe",
          regime: "trending"
        )

        payload = described_class.call(calendar_day: nil, trades_day: nil, trades_limit: nil)

        expect(payload[:stats][:total_pnl_usd]).to eq(34.38)
        expect(payload[:stats][:total_equity_usd]).to eq(1034.38)
      end

      it "reports headline total_equity from ledger cash (excludes unrealized in stats)" do
        session = create(:trading_session, status: "running")
        allow(Trading::PaperWalletPublisher).to receive(:wallet_snapshot!).and_return(
          "total_equity_usd" => 200.0,
          "total_equity_inr" => 17_000,
          "unrealized_pnl_usd" => 50.0,
          "paper_mode" => true,
          "updated_at" => Time.current.iso8601,
          "stale" => false
        )

        payload = described_class.call(calendar_day: nil, trades_day: nil, trades_limit: nil)

        expect(payload[:stats][:total_equity_usd]).to eq(150.0)
        expect(payload[:stats][:total_equity_inr]).to eq(12_750)
      end
    end
  end
end
