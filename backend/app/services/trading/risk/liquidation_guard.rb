# frozen_string_literal: true

module Trading
  module Risk
    # LiquidationGuard classifies position safety from margin usage.
    class LiquidationGuard
      THRESHOLD = ENV.fetch("RISK_DANGER_MARGIN_RATIO", "0.9").to_d

      # @param position [Position]
      # @param mark_price [Numeric]
      # @return [Symbol] :safe, :danger, :liquidation
      def self.call(position:, mark_price:)
        return :safe if position.size.to_d.zero?

        margin = MarginCalculator.call(position: position, mark_price: mark_price)

        if margin.margin_ratio >= 1.to_d
          :liquidation
        elsif margin.margin_ratio >= THRESHOLD
          :danger
        else
          :safe
        end
      end
    end
  end
end
