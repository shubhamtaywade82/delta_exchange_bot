# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::MatchingEngine do
  let(:order_book) { PaperTrading::OrderBook.new }
  let(:engine) { described_class.new(order_book: order_book) }
  let(:wallet) { create(:paper_wallet) }
  let(:product) { create(:paper_product_snapshot) }
  let(:signal) { create(:paper_trading_signal, paper_wallet: wallet, product_id: product.product_id) }

  before do
    order_book.update!(
      bids: [ [ 99, 2 ], [ 98, 3 ] ],
      asks: [ [ 101, 1 ], [ 102, 5 ] ]
    )
  end

  describe "#execute" do
    it "fills across multiple levels" do
      order = create(:paper_order,
        paper_wallet: wallet,
        paper_product_snapshot: product,
        paper_trading_signal: signal,
        side: "buy",
        order_type: "market_order",
        size: 3)

      fills = engine.execute(order)

      expect(fills).to eq(
        [
          { price: BigDecimal("101"), qty: 1, liquidity: :taker },
          { price: BigDecimal("102"), qty: 2, liquidity: :taker }
        ]
      )
    end

    it "handles insufficient liquidity" do
      order = create(:paper_order,
        paper_wallet: wallet,
        paper_product_snapshot: product,
        paper_trading_signal: signal,
        side: "buy",
        order_type: "market_order",
        size: 20)

      fills = engine.execute(order)

      expect(fills.sum { |fill| fill[:qty] }).to eq(6)
      expect(fills.last).to eq(price: BigDecimal("102"), qty: 5, liquidity: :taker)
    end

    it "does not fill if not crossing spread" do
      order = create(:paper_order,
        paper_wallet: wallet,
        paper_product_snapshot: product,
        paper_trading_signal: signal,
        side: "buy",
        order_type: "limit_order",
        limit_price: BigDecimal("100"),
        size: 1)

      fills = engine.execute(order)

      expect(fills).to eq([])
    end
  end
end
