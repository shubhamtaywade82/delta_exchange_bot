require "rails_helper"

RSpec.describe Position, type: :model do
  describe "validations" do
    it "defaults to init status" do
      position = described_class.new(symbol: "BTCUSD", side: "buy", size: 1)

      position.validate

      expect(position.status).to eq("init")
    end

    it "rejects unsupported statuses" do
      position = described_class.new(symbol: "BTCUSD", side: "buy", size: 1, status: "open")

      expect(position).not_to be_valid
      expect(position.errors[:status]).to include("is not included in the list")
    end
  end

  describe "#transition_to!" do
    it "allows valid transition chain" do
      position = described_class.create!(symbol: "BTCUSD", side: "buy", size: 1)

      expect { position.transition_to!("entry_pending") }
        .to change { position.reload.status }
        .from("init").to("entry_pending")

      expect { position.transition_to!("filled") }
        .to change { position.reload.status }
        .from("entry_pending").to("filled")
    end

    it "raises when transition is invalid" do
      position = described_class.create!(symbol: "BTCUSD", side: "buy", size: 1)

      expect { position.transition_to!("closed") }
        .to raise_error(Position::InvalidTransitionError, "init -> closed is invalid")
    end
  end

  describe "#recalculate_from_orders!" do
    let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }

    it "derives partially_filled from linked orders" do
      position = described_class.create!(symbol: "BTCUSD", side: "buy", size: 1)

      order = Order.create!(
        trading_session: session,
        position: position,
        symbol: "BTCUSD",
        side: "buy",
        size: 2,
        filled_qty: 1,
        order_type: "limit_order",
        status: "partially_filled",
        client_order_id: SecureRandom.uuid,
        idempotency_key: "idem-pos-1"
      )

      Fill.create!(
        order: order,
        exchange_fill_id: "fill-pos-recalc-1",
        quantity: 1,
        price: 50_000,
        filled_at: Time.current
      )

      position.recalculate_from_orders!

      expect(position.reload.status).to eq("partially_filled")
      expect(position.size.to_d).to eq(1.to_d)
    end
  end
end
