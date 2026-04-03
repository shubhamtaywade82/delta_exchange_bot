# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Risk::PortfolioSnapshot do
  around do |example|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous_cache
  end

  describe ".from_positions" do
    it "sums only mark-to-market unrealized; ignores position.pnl_usd on open rows" do
      portfolio = create(:portfolio)
      create(
        :position,
        portfolio: portfolio,
        symbol: "BTCUSD",
        side: "short",
        status: "filled",
        entry_price: 100.0,
        size: 1.0,
        leverage: 10,
        margin: 10.0,
        pnl_usd: -50.0
      )
      Rails.cache.write("ltp:BTCUSD", 99.0)

      result = described_class.from_positions(Position.where(portfolio_id: portfolio.id))

      expect(result.total_pnl).to eq(1.to_d)
    end
  end
end
