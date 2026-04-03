# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Handlers::OrderHandler do
  let(:session) { create(:trading_session, capital: 10_000) }
  let(:portfolio) { session.portfolio }

  let(:event) do
    Struct.new(:exchange_order_id, :filled_qty, :avg_fill_price, :status).new(
      order.exchange_order_id,
      order.filled_qty,
      order.avg_fill_price,
      order.status
    )
  end

  before do
    allow(Finance::UsdInrRate).to receive(:current).and_return(BigDecimal("83"))
    allow(Trading::EventBus).to receive(:publish)
    allow(OrdersRepository).to receive(:update_from_fill).and_return(order)
  end

  describe "#call" do
    context "when closing a long with a sell fill" do
      let(:order) do
        create(
          :order,
          trading_session: session,
          symbol: "BTCUSD",
          side: "sell",
          status: "filled",
          filled_qty: 1.0,
          avg_fill_price: 51_000.0,
          exchange_order_id: "EX-H-SELL-1"
        )
      end

      before do
        Position.create!(
          portfolio: portfolio,
          symbol: "BTCUSD",
          side: "long",
          status: "filled",
          size: 1.0,
          entry_price: 50_000.0,
          leverage: 10,
          product_id: 84,
          entry_time: 1.hour.ago
        )
      end

      it "persists a trade using the pre-close position snapshot" do
        freeze_time do
          described_class.new(event).call
        end

        trade = Trade.find_by(portfolio_id: portfolio.id, symbol: "BTCUSD")
        expect(trade).to be_present
        expect(trade.side).to eq("long")
        expect(trade.exit_price).to eq(order.avg_fill_price)
        expect(trade.pnl_usd).to eq(1000.0)
      end

      it "publishes a position update scoped to the order portfolio" do
        described_class.new(event).call

        expect(Trading::EventBus).to have_received(:publish).with(:position_updated, kind_of(Trading::Events::PositionUpdated))
      end
    end

    context "when closing a short with a buy fill" do
      let(:order) do
        create(
          :order,
          trading_session: session,
          symbol: "ETHUSD",
          side: "buy",
          size: 2.0,
          status: "filled",
          filled_qty: 2.0,
          avg_fill_price: 2900.0,
          exchange_order_id: "EX-H-BUY-CLOSE-SHORT"
        )
      end

      before do
        Position.create!(
          portfolio: portfolio,
          symbol: "ETHUSD",
          side: "short",
          status: "filled",
          size: 2.0,
          entry_price: 3000.0,
          leverage: 10,
          product_id: 3,
          entry_time: 1.hour.ago
        )
      end

      it "records positive PnL when price falls on a short" do
        freeze_time do
          described_class.new(event).call
        end

        trade = Trade.find_by(portfolio_id: portfolio.id, symbol: "ETHUSD")
        expect(trade.pnl_usd).to eq(200.0)
      end
    end

    context "when another portfolio has the same symbol open" do
      let(:other_session) { create(:trading_session, capital: 2000.0) }
      let(:order) do
        create(
          :order,
          trading_session: session,
          symbol: "BTCUSD",
          side: "sell",
          status: "filled",
          filled_qty: 1.0,
          avg_fill_price: 52_000.0,
          exchange_order_id: "EX-H-SELL-ISO"
        )
      end

      before do
        Position.create!(
          portfolio: portfolio,
          symbol: "BTCUSD",
          side: "long",
          status: "filled",
          size: 1.0,
          entry_price: 50_000.0,
          leverage: 10,
          product_id: 84,
          entry_time: 1.hour.ago
        )
        Position.create!(
          portfolio: other_session.portfolio,
          symbol: "BTCUSD",
          side: "long",
          status: "filled",
          size: 1.0,
          entry_price: 48_000.0,
          leverage: 10,
          product_id: 84,
          entry_time: 1.hour.ago
        )
      end

      it "closes only the session portfolio position" do
        described_class.new(event).call

        expect(Position.find_by(portfolio_id: portfolio.id, symbol: "BTCUSD").status).to eq("closed")
        expect(Position.find_by(portfolio_id: other_session.portfolio.id, symbol: "BTCUSD").status).to eq("filled")
      end
    end

    context "when the order is not filled" do
      let(:order) do
        create(
          :order,
          trading_session: session,
          symbol: "BTCUSD",
          side: "buy",
          status: "submitted",
          exchange_order_id: "EX-NOT-FILLED"
        )
      end

      it "does not touch positions or publish" do
        described_class.new(event).call

        expect(Trading::EventBus).not_to have_received(:publish)
      end
    end
  end
end
