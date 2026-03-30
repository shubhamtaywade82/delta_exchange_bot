require "rails_helper"

RSpec.describe Order, type: :model do
  let(:session) { create(:trading_session) }

  it "is valid with required attributes" do
    order = build(:order, trading_session: session, status: "created")

    expect(order).to be_valid
  end

  it "enforces transitions" do
    order = create(:order, trading_session: session, status: "created")

    order.transition_to!("submitted")
    expect(order.reload.status).to eq("submitted")

    expect { order.transition_to!("created") }
      .to raise_error(Order::InvalidTransitionError)
  end

  it "applies cumulative fills" do
    order = create(:order, trading_session: session, status: "submitted", size: 2)

    order.apply_fill!(cumulative_qty: 1, avg_fill_price: 49_900, exchange_status: "open")
    expect(order.reload.status).to eq("partially_filled")

    order.apply_fill!(cumulative_qty: 2, avg_fill_price: 49_950, exchange_status: "filled")
    expect(order.reload.status).to eq("filled")
  end
end
