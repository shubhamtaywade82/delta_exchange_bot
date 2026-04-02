# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Risk::MarginAffordability do
  let(:portfolio) { create(:portfolio, balance: 100, available_balance: 100, used_margin: 0) }
  let(:session) { create(:trading_session, portfolio: portfolio, capital: 100.0, leverage: 10, status: "running") }
  let(:position) do
    create(:position,
           portfolio: portfolio,
           symbol: "BTCUSD",
           side: "long",
           status: "init",
           leverage: 10,
           contract_value: 0.001,
           entry_price: nil,
           size: nil,
           margin: nil)
  end

  before do
    allow(Trading::Risk::PositionLotSize).to receive(:multiplier_for).and_return(BigDecimal("0.001"))
  end

  describe ".verify!" do
    it "allows when incremental margin fits available_balance" do
      expect do
        described_class.verify!(
          portfolio: portfolio,
          symbol: "BTCUSD",
          order_side: "buy",
          order_size: 1,
          fill_price: 50_000,
          position: position,
          session: session
        )
      end.not_to raise_error
    end

    it "raises when incremental margin exceeds available_balance" do
      expect do
        described_class.verify!(
          portfolio: portfolio,
          symbol: "BTCUSD",
          order_side: "buy",
          order_size: 10_000,
          fill_price: 50_000,
          position: position,
          session: session
        )
      end.to raise_error(Trading::RiskManager::RiskError, /insufficient cash for margin/)
    end
  end
end
