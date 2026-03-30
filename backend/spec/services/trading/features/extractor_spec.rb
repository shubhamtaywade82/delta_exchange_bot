require "rails_helper"

RSpec.describe Trading::Features::Extractor do
  it "builds feature hash" do
    book = Trading::Orderbook::Book.new
    book.update!(bids: [[100, 10]], asks: [[101, 9]])
    trades = [{ price: 100 }, { price: 102 }]

    features = described_class.call(book: book, trades: trades)

    expect(features[:spread]).to eq(1.0)
    expect(features[:trade_intensity]).to eq(2)
    expect(features[:momentum]).to eq(2.0)
  end
end
