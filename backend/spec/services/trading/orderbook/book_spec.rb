require "rails_helper"

RSpec.describe Trading::Orderbook::Book do
  it "updates and computes spread" do
    book = described_class.new
    book.update!(bids: [[100, 2]], asks: [[101, 3]])

    expect(book.best_bid.to_d).to eq(100.to_d)
    expect(book.best_ask.to_d).to eq(101.to_d)
    expect(book.spread.to_d).to eq(1.to_d)
  end
end
