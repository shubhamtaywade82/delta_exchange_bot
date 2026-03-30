require "rails_helper"

RSpec.describe Trading::Microstructure::Imbalance do
  it "calculates positive imbalance" do
    book = Trading::Orderbook::Book.new
    book.update!(bids: [[100, 10]], asks: [[101, 2]])

    expect(described_class.calculate(book)).to be > 0
  end
end
