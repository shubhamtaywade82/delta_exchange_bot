require "rails_helper"

RSpec.describe Fill, type: :model do
  it "is valid with required attributes" do
    fill = build(:fill)

    expect(fill).to be_valid
  end

  it "enforces unique exchange_fill_id" do
    create(:fill, exchange_fill_id: "F-UNIQ")
    dup = build(:fill, exchange_fill_id: "F-UNIQ")

    expect(dup).not_to be_valid
  end
end
