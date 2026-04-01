# frozen_string_literal: true

module Trading
  # Mark-based liquidation pass using existing Risk::Engine + Executor (no second close path).
  class LiquidationEngine
    # @param position [Position]
    # @param mark_price [Numeric, nil] falls back to MarkPrice.for_symbol
    def self.evaluate_and_act!(position, mark_price: nil)
      mark_price ||= MarkPrice.for_symbol(position.symbol)
      return if mark_price.blank? || position.size.to_d.zero?

      portfolio = Risk::PortfolioSnapshot.current
      result = Risk::Engine.evaluate(position: position, mark_price: mark_price, portfolio: portfolio)
      Risk::Executor.handle!(position: position, signal: result[:liquidation], mark_price: mark_price)
    end
  end
end
