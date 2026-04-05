# frozen_string_literal: true

require "rails_helper"

RSpec.describe PositionsRepository do
  let(:session) { create(:trading_session, capital: 10_000) }
  let(:portfolio) { session.portfolio }

  def open_position(attrs = {})
    Position.create!(
      { portfolio: portfolio, symbol: "BTCUSD", status: "filled", size: 1.0,
        entry_price: 50_000.0, leverage: 10, product_id: 84 }.merge(attrs)
    )
  end

  describe ".closing_fill?" do
    it "returns false when no active position exists for the order portfolio" do
      order = create(:order, trading_session: session, symbol: "BTCUSD", side: "sell", status: "filled")
      expect(described_class.closing_fill?(order)).to be(false)
    end

    it "returns true when a long is open and the fill is a sell" do
      open_position(side: "long")
      order = create(:order, trading_session: session, symbol: "BTCUSD", side: "sell", status: "filled")
      expect(described_class.closing_fill?(order)).to be(true)
    end

    it "returns false when a long is open and the fill is a buy" do
      open_position(side: "long")
      order = create(:order, trading_session: session, symbol: "BTCUSD", side: "buy", status: "filled")
      expect(described_class.closing_fill?(order)).to be(false)
    end

    it "returns true when a short is open and the fill is a buy" do
      open_position(side: "short")
      order = create(:order, trading_session: session, symbol: "BTCUSD", side: "buy", status: "filled")
      expect(described_class.closing_fill?(order)).to be(true)
    end

    it "returns false when a short is open and the fill is a sell" do
      open_position(side: "short")
      order = create(:order, trading_session: session, symbol: "BTCUSD", side: "sell", status: "filled")
      expect(described_class.closing_fill?(order)).to be(false)
    end

    it "treats legacy position side buy as long for closing logic" do
      open_position(side: "buy")
      order = create(:order, trading_session: session, symbol: "BTCUSD", side: "sell", status: "filled")
      expect(described_class.closing_fill?(order)).to be(true)
    end
  end

  describe ".open_for" do
    let(:other_session) { create(:trading_session, capital: 500.0) }

    it "returns the first active row for the symbol when portfolio_id is omitted" do
      open_position(side: "long")
      expect(described_class.open_for("BTCUSD")).to be_present
    end

    it "returns only positions for the given portfolio when portfolio_id is set" do
      open_position(side: "long")
      Position.create!(
        portfolio: other_session.portfolio, symbol: "BTCUSD", side: "long", status: "filled",
        size: 1.0, entry_price: 40_000.0, leverage: 10, product_id: 84
      )

      found = described_class.open_for("BTCUSD", portfolio_id: portfolio.id)
      expect(found.portfolio_id).to eq(portfolio.id)
    end
  end

  describe ".apply_fill_from_order!" do
    it "opens a long on a buy when flat" do
      order = create(
        :order,
        trading_session: session,
        symbol: "BTCUSD",
        side: "buy",
        status: "filled",
        filled_qty: 1.0,
        avg_fill_price: 50_000.0,
        exchange_order_id: "EX-OPEN-LONG"
      )

      described_class.apply_fill_from_order!(order)

      pos = Position.find_by!(portfolio_id: portfolio.id, symbol: "BTCUSD")
      expect(pos.side).to eq("long")
      expect(pos.status).to eq("filled")
    end

    it "opens a short on a sell when flat" do
      order = create(
        :order,
        trading_session: session,
        symbol: "BTCUSD",
        side: "sell",
        status: "filled",
        filled_qty: 1.0,
        avg_fill_price: 50_000.0,
        exchange_order_id: "EX-OPEN-SHORT"
      )

      described_class.apply_fill_from_order!(order)

      pos = Position.find_by!(portfolio_id: portfolio.id, symbol: "BTCUSD")
      expect(pos.side).to eq("short")
    end

    it "closes a long on a sell" do
      open_position(side: "long")
      order = create(
        :order,
        trading_session: session,
        symbol: "BTCUSD",
        side: "sell",
        status: "filled",
        filled_qty: 1.0,
        avg_fill_price: 51_000.0,
        exchange_order_id: "EX-CLOSE-LONG"
      )

      described_class.apply_fill_from_order!(order)

      expect(Position.where(portfolio_id: portfolio.id, symbol: "BTCUSD").pluck(:status)).to eq(%w[closed])
    end
  end
end
