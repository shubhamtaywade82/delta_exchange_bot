require "rails_helper"

RSpec.describe Trading::Execution::DecisionEngine do
  it "chooses maker buy for mild long signal" do
    book = Trading::Orderbook::Book.new
    book.update!(bids: [[100, 10]], asks: [[101, 9]])

    expect(described_class.call(signal: :long, book: book)).to eq(:maker_buy)
  end
end
