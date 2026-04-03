require "rails_helper"

RSpec.describe Trading::EmergencyShutdown do
  let(:session) { create(:trading_session, strategy: "multi_timeframe", capital: 1000.0) }
  let(:client)  { double("DeltaExchange::Client") }

  before do
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(false)
    allow(client).to receive(:cancel_order).and_return(true)
    allow(client).to receive(:place_order).and_return({ id: "CLOSE-001" })
    allow(Trading::Learning::CreditAssigner).to receive(:finalize_trade!).and_return(
      instance_double(
        Trade,
        id: 1,
        symbol: "BTCUSD",
        exit_price: 50_000.0,
        pnl_usd: 0.0,
        pnl_inr: 0.0,
        duration_seconds: 0
      )
    )
    allow(Trading::Learning::OnlineUpdater).to receive(:update!)
    allow(Trading::Learning::Metrics).to receive(:update)
    allow(Trading::Learning::AiRefinementTrigger).to receive(:call)
  end

  describe ".call" do
    it "cancels all pending/open orders for the session" do
      order = Order.create!(
        trading_session: session, symbol: "BTCUSD", side: "buy",
        size: 1.0, price: 50000.0, order_type: "limit_order",
        status: "submitted", idempotency_key: "key-ks-1", client_order_id: "cid-ks-1",
        exchange_order_id: "EX-001"
      )
      described_class.call(session.id, client: client)
      expect(order.reload.status).to eq("cancelled")
      expect(client).to have_received(:cancel_order).with("EX-001")
    end

    it "closes all open positions by placing market orders" do
      Position.create!(portfolio: session.portfolio, symbol: "BTCUSD", side: "long", status: "filled",
                       size: 1.0, entry_price: 50000.0, leverage: 10, product_id: 84)
      described_class.call(session.id, client: client)
      expect(client).to have_received(:place_order).with(hash_including(side: "sell", order_type: "market_order"))
      expect(Position.find_by(symbol: "BTCUSD").status).to eq("closed")
    end

    it "marks the session as stopped" do
      described_class.call(session.id, client: client)
      expect(session.reload.status).to eq("stopped")
    end

    context "when another session has open positions" do
      let(:other_session) { create(:trading_session, strategy: "multi_timeframe", capital: 500.0) }

      it "closes only positions for the target session portfolio" do
        target_position = Position.create!(
          portfolio: session.portfolio, symbol: "BTCUSD", side: "long", status: "filled",
          size: 1.0, entry_price: 50_000.0, leverage: 10, product_id: 84
        )
        other_position = Position.create!(
          portfolio: other_session.portfolio, symbol: "ETHUSD", side: "long", status: "filled",
          size: 1.0, entry_price: 3000.0, leverage: 10, product_id: 3
        )

        described_class.call(session.id, client: client)

        expect(target_position.reload.status).to eq("closed")
        expect(other_position.reload.status).to eq("filled")
        expect(client).to have_received(:place_order).once
      end

      it "does not cancel orders belonging to the other session" do
        other_order = Order.create!(
          trading_session: other_session, symbol: "ETHUSD", side: "buy",
          size: 1.0, price: 3000.0, order_type: "limit_order",
          status: "submitted", idempotency_key: "key-other-1", client_order_id: "cid-other-1",
          exchange_order_id: "EX-OTHER"
        )
        target_order = Order.create!(
          trading_session: session, symbol: "BTCUSD", side: "buy",
          size: 1.0, price: 50_000.0, order_type: "limit_order",
          status: "submitted", idempotency_key: "key-target-1", client_order_id: "cid-target-1",
          exchange_order_id: "EX-TARGET"
        )

        described_class.call(session.id, client: client)

        expect(target_order.reload.status).to eq("cancelled")
        expect(other_order.reload.status).to eq("submitted")
        expect(client).to have_received(:cancel_order).with("EX-TARGET").once
        expect(client).not_to have_received(:cancel_order).with("EX-OTHER")
      end
    end
  end

  describe ".force_exit_position" do
    it "places a sell order for a long position" do
      position = Position.create!(portfolio: session.portfolio, symbol: "BTCUSD", side: "long", status: "filled",
                                  size: 1.0, entry_price: 50000.0, leverage: 10, product_id: 84)
      described_class.force_exit_position(position, client)
      expect(client).to have_received(:place_order).with(
        hash_including(side: "sell", product_id: 84, order_type: "market_order")
      )
      expect(position.reload.status).to eq("closed")
    end

    it "places a buy order for a short position" do
      position = Position.create!(portfolio: session.portfolio, symbol: "ETHUSD", side: "short", status: "filled",
                                  size: 2.0, entry_price: 3000.0, leverage: 15, product_id: 3)
      described_class.force_exit_position(position, client)
      expect(client).to have_received(:place_order).with(hash_including(side: "buy"))
    end
  end
end
