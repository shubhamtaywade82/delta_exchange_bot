# frozen_string_literal: true

require "rails_helper"

RSpec.describe Finance::UsdInrRate do
  describe ".current" do
    it "returns Bot::Config usd_to_inr_rate when load succeeds" do
      config = instance_double(Bot::Config, usd_to_inr_rate: 90.5)
      allow(Bot::Config).to receive(:load).and_return(config)
      expect(described_class.current).to eq(90.5)
    end

    it "returns fallback when Bot::Config.load raises ValidationError" do
      allow(Bot::Config).to receive(:load).and_raise(Bot::Config::ValidationError, "bad")
      expect(described_class.current).to eq(described_class::FALLBACK)
    end

    it "returns fallback when Bot::Config.load raises other errors" do
      allow(Bot::Config).to receive(:load).and_raise(StandardError, "boom")
      expect(described_class.current).to eq(described_class::FALLBACK)
    end
  end
end
