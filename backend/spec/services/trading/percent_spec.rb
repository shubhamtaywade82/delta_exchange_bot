# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Percent do
  describe ".as_fraction" do
    it "treats values > 1 as legacy percent points" do
      expect(described_class.as_fraction(1.5)).to eq(0.015)
      expect(described_class.as_fraction(5)).to eq(0.05)
    end

    it "leaves fractional values unchanged" do
      expect(described_class.as_fraction(0.015)).to eq(0.015)
      expect(described_class.as_fraction(1.0)).to eq(1.0)
      expect(described_class.as_fraction(0.5)).to eq(0.5)
    end
  end
end
