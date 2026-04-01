# frozen_string_literal: true

require "rails_helper"

RSpec.describe Finance::UsdInrRate do
  describe ".current" do
    it "returns the Setting value when positive" do
      row = instance_double(Setting, value: "90.5")
      allow(Setting).to receive(:find_by).with(key: "usd_to_inr_rate").and_return(row)
      expect(described_class.current).to eq(90.5)
    end

    it "returns 85.0 when setting is missing" do
      allow(Setting).to receive(:find_by).with(key: "usd_to_inr_rate").and_return(nil)
      expect(described_class.current).to eq(85.0)
    end

    it "returns 85.0 when value is zero or blank" do
      row = instance_double(Setting, value: "0")
      allow(Setting).to receive(:find_by).with(key: "usd_to_inr_rate").and_return(row)
      expect(described_class.current).to eq(85.0)
    end
  end
end
