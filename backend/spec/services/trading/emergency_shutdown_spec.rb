require "rails_helper"

RSpec.describe Trading::EmergencyShutdown do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:client)  { double("DeltaExchange::Client") }

  before do
    allow(Trading::PaperTrading).to receive(:enabled?).and_return(false)
    allow(client).to receive(:cancel_order).and_return(true)
    allow(client).to receive(:place_order).and_return({ id: "CLOSE-001" })
    allow(Trading::Learning::CreditAssigner).to receive(:finalize_trade!).and_return(instance_double(Trade, id: 1))
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
      Position.create!(symbol: "BTCUSD", side: "long", status: "filled",
                       size: 1.0, entry_price: 50000.0, leverage: 10, product_id: 84)
      described_class.call(session.id, client: client)
      expect(client).to have_received(:place_order).with(hash_including(side: "sell", order_type: "market_order"))
      expect(Position.find_by(symbol: "BTCUSD").status).to eq("closed")
    end

    it "marks the session as stopped" do
      described_class.call(session.id, client: client)
      expect(session.reload.status).to eq("stopped")
    end
  end

  describe ".force_exit_position" do
    it "places a sell order for a long position" do
      position = Position.create!(symbol: "BTCUSD", side: "long", status: "filled",
                                  size: 1.0, entry_price: 50000.0, leverage: 10, product_id: 84)
      described_class.force_exit_position(position, client)
      expect(client).to have_received(:place_order).with(
        hash_including(side: "sell", product_id: 84, order_type: "market_order")
      )
      expect(position.reload.status).to eq("closed")
    end

    it "places a buy order for a short position" do
      position = Position.create!(symbol: "ETHUSD", side: "short", status: "filled",
                                  size: 2.0, entry_price: 3000.0, leverage: 15, product_id: 3)
      described_class.force_exit_position(position, client)
      expect(client).to have_received(:place_order).with(hash_including(side: "buy"))
    end
  end
end
