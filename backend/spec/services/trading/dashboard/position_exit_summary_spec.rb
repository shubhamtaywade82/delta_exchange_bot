# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Dashboard::PositionExitSummary do
  let(:portfolio) { create(:portfolio) }

  def position(attrs)
    build(:position, portfolio: portfolio, **attrs)
  end

  describe ".call" do
    it "returns empty hash when mark is not positive" do
      pos = position(side: "short", stop_price: 101.0)
      expect(described_class.call(position: pos, mark_price: nil)).to eq({})
      expect(described_class.call(position: pos, mark_price: 0)).to eq({})
    end

    it "computes trailing room for a short (stop above mark)" do
      pos = position(side: "short", stop_price: 105.0, liquidation_price: nil)
      h = described_class.call(position: pos, mark_price: 100.0)

      expect(h[:trailing_stop][:room_pct]).to eq(5.0)
      expect(h[:trailing_stop][:at_risk]).to be(false)
      expect(h[:nearest_exit][:kind]).to eq("trailing_stop")
    end

    it "flags at_risk when short mark is at or past stop" do
      pos = position(side: "short", stop_price: 100.0)
      h = described_class.call(position: pos, mark_price: 100.0)

      expect(h[:trailing_stop][:at_risk]).to be(true)
      expect(h[:nearest_exit][:note]).to eq("at_or_past_stop")
    end

    it "computes trailing room for a long (stop below mark)" do
      pos = position(side: "long", stop_price: 95.0)
      h = described_class.call(position: pos, mark_price: 100.0)

      expect(h[:trailing_stop][:room_pct]).to eq(5.0)
      expect(h[:trailing_stop][:at_risk]).to be(false)
    end

    it "prefers the tighter of trailing stop and liquidation distance" do
      pos = position(side: "short", stop_price: 110.0, liquidation_price: 115.0)
      h = described_class.call(position: pos, mark_price: 100.0)

      expect(h[:trailing_stop][:room_pct]).to eq(10.0)
      expect(h[:liquidation][:distance_pct]).to eq(15.0)
      expect(h[:nearest_exit][:kind]).to eq("trailing_stop")
    end

    it "omits liquidation when distance fraction is negative" do
      pos = position(side: "short", stop_price: 105.0, liquidation_price: 90.0)
      h = described_class.call(position: pos, mark_price: 100.0)

      expect(h[:liquidation]).to be_nil
      expect(h[:nearest_exit][:kind]).to eq("trailing_stop")
    end
  end
end
