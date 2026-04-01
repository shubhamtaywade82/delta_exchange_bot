# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Ledger::NetPositionCalculator do
  def fill(qty, price, side: "buy", id: 1)
    session = create(:trading_session)
    order = create(:order, trading_session: session, side: side, symbol: "BTCUSD")
    create(:fill, order: order, quantity: qty, price: price, exchange_fill_id: "f-#{id}")
  end

  describe ".from_fills" do
    it "sums same-side buys into average entry and positive signed qty" do
      a = fill(1, 50_000, id: 1)
      b = fill(2, 53_000, id: 2)
      result = described_class.from_fills([a, b])
      expect(result.signed_qty).to eq(3)
      expect(result.avg_entry.to_d).to eq((50_000 + 106_000).to_d / 3)
      expect(result.cumulative_realized_pnl).to eq(0)
    end

    it "realizes PnL when selling to flat" do
      buy = fill(2, 50_000, side: "buy", id: 1)
      sell = fill(2, 52_000, side: "sell", id: 2)
      result = described_class.from_fills([buy, sell])
      expect(result.signed_qty).to eq(0)
      expect(result.avg_entry).to be_nil
      expect(result.cumulative_realized_pnl).to eq((52_000 - 50_000) * 2)
    end

    it "opens short remainder after closing long (flip)" do
      buy = fill(2, 50_000, side: "buy", id: 1)
      sell = fill(3, 48_000, side: "sell", id: 2)
      result = described_class.from_fills([buy, sell])
      expect(result.signed_qty).to eq(-1)
      expect(result.avg_entry.to_d).to eq(48_000.to_d)
      realized = (48_000 - 50_000) * 2
      expect(result.cumulative_realized_pnl).to eq(realized)
    end
  end

  describe ".realized_delta_for_append" do
    it "returns incremental realized for the last fill only" do
      buy = fill(1, 50_000, side: "buy", id: 1)
      sell = fill(1, 51_000, side: "sell", id: 2)
      delta = described_class.realized_delta_for_append([buy], sell)
      expect(delta).to eq(1000)
    end
  end
end
