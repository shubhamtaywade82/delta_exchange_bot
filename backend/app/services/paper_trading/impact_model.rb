# frozen_string_literal: true

module PaperTrading
  # Applies deterministic, non-linear market impact over matched level price.
  class ImpactModel
    # @param price [BigDecimal, Numeric, String]
    # @param quantity [Integer, BigDecimal]
    # @param depth [BigDecimal, Numeric, String]
    # @param side [String, Symbol] buy or sell
    # @return [BigDecimal]
    def self.apply(price:, quantity:, depth:, side:)
      normalized_price = price.to_d
      normalized_depth = depth.to_d
      return normalized_price unless normalized_depth.positive?

      impact_ratio = quantity.to_d / normalized_depth
      impact = impact_coefficient * impact_ratio**BigDecimal("1.5")
      buy_side?(side) ? normalized_price + impact : normalized_price - impact
    end

    def self.impact_coefficient
      ENV.fetch("PAPER_IMPACT_COEFF", "0.1").to_d
    end
    private_class_method :impact_coefficient

    def self.buy_side?(side)
      side.to_s == "buy"
    end
    private_class_method :buy_side?
  end
end
