# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrdersRepository do
  describe ".close_position" do
    it "persists realized PnL on the position and trade using the same mark-to-exit math as live unrealized" do
      portfolio = create(:portfolio)
      session = create(:trading_session, portfolio: portfolio, strategy: "multi_timeframe")
      position = create(
        :position,
        portfolio: portfolio,
        symbol: "BTCUSD",
        side: "short",
        status: "filled",
        size: 1.0,
        entry_price: 66_577.94,
        leverage: 10,
        contract_value: 1.0,
        strategy: "multi_timeframe",
        regime: "trending",
        entry_time: 30.minutes.ago,
        pnl_usd: nil,
        pnl_inr: nil
      )

      allow(Trading::Learning::OnlineUpdater).to receive(:update!)
      allow(Trading::Learning::Metrics).to receive(:update)
      allow(Trading::Learning::AiRefinementTrigger).to receive(:call)
      allow(Trading::TelegramNotifications).to receive(:deliver).and_yield(double.as_null_object)
      allow(Trading::PaperTrading).to receive(:enabled?).and_return(true)

      balance_before = portfolio.reload.balance.to_d
      mark = 66_671.18
      described_class.close_position(position_id: position.id, reason: "LIQUIDATION_EXIT", mark_price: mark)

      position.reload
      expect(position.pnl_usd.to_f).to be_within(0.02).of(-93.24)
      expect(portfolio.reload.balance.to_d).to eq(balance_before + position.pnl_usd.to_d)

      trade = Trade.order(id: :desc).first
      expect(trade).to be_present
      expect(trade.pnl_usd.to_f).to be_within(0.02).of(-93.24)
      expect(trade.exit_price.to_f).to eq(mark)
    end

    it "does not create a second trade when close is invoked again on the same position" do
      portfolio = create(:portfolio)
      create(:trading_session, portfolio: portfolio, strategy: "multi_timeframe")
      position = create(
        :position,
        portfolio: portfolio,
        symbol: "BTCUSD",
        side: "short",
        status: "filled",
        size: 1.0,
        entry_price: 66_577.94,
        leverage: 10,
        contract_value: 1.0,
        strategy: "multi_timeframe",
        regime: "trending",
        entry_time: 30.minutes.ago,
        pnl_usd: nil,
        pnl_inr: nil
      )

      allow(Trading::Learning::OnlineUpdater).to receive(:update!)
      allow(Trading::Learning::Metrics).to receive(:update)
      allow(Trading::Learning::AiRefinementTrigger).to receive(:call)
      allow(Trading::TelegramNotifications).to receive(:deliver).and_yield(double.as_null_object)

      mark = 66_671.18
      described_class.close_position(position_id: position.id, reason: "LIQUIDATION_EXIT", mark_price: mark)

      expect do
        described_class.close_position(position_id: position.id, reason: "LIQUIDATION_EXIT", mark_price: mark)
      end.not_to change(Trade, :count)
    end
  end
end
