# frozen_string_literal: true

require "rails_helper"

RSpec.describe SymbolConfig, type: :model do
  describe "persistence" do
    it "stores symbol, leverage, enabled, and product_id" do
      config = described_class.create!(
        symbol: "BTCUSD",
        leverage: 10,
        enabled: true,
        product_id: 84
      )

      expect(config.reload).to have_attributes(
        symbol: "BTCUSD",
        leverage: 10,
        enabled: true,
        product_id: 84
      )
    end

    it "updates the enabled flag" do
      config = described_class.create!(symbol: "ETHUSD", leverage: 5, enabled: true)

      config.update!(enabled: false)

      expect(config.reload.enabled).to be(false)
    end
  end
end
