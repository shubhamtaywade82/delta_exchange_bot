# frozen_string_literal: true

module Trading
  module Risk
    # Engine orchestrates per-position and portfolio-level risk evaluation.
    class Engine
      # @param position [Position]
      # @param mark_price [Numeric]
      # @param portfolio [Trading::Risk::PortfolioSnapshot::Result]
      # @return [Hash]
      def self.evaluate(position:, mark_price:, portfolio:)
        pnl = PositionRisk.call(position: position, mark_price: mark_price)
        margin = MarginCalculator.call(position: position, mark_price: mark_price)
        liquidation = LiquidationGuard.call(position: position, mark_price: mark_price)
        portfolio_guard = PortfolioGuard.call(portfolio: portfolio)

        { pnl: pnl, margin: margin, liquidation: liquidation, portfolio_guard: portfolio_guard }
      end
    end
  end
end
