# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::SimulationProfile do
  describe ".orderbook_simulator_enabled?" do
    it "is true when ENV is an affirmative token" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PAPER_USE_ORDERBOOK_SIMULATOR").and_return("true")

      expect(described_class.orderbook_simulator_enabled?).to be true
    end

    it "is false when ENV is a negative token" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PAPER_USE_ORDERBOOK_SIMULATOR").and_return("false")

      expect(described_class.orderbook_simulator_enabled?).to be false
    end

    it "is false when ENV is unset and not production" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PAPER_USE_ORDERBOOK_SIMULATOR").and_return(nil)
      allow(Rails.env).to receive(:production?).and_return(false)

      expect(described_class.orderbook_simulator_enabled?).to be false
    end

    it "is true when ENV is unset and Rails.env is production" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PAPER_USE_ORDERBOOK_SIMULATOR").and_return(nil)
      allow(Rails.env).to receive(:production?).and_return(true)

      expect(described_class.orderbook_simulator_enabled?).to be true
    end
  end
end
