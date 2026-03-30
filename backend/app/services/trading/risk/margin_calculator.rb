# frozen_string_literal: true

module Trading
  module Risk
    # MarginCalculator computes position value and margin usage from live mark price.
    class MarginCalculator
      Result = Struct.new(:position_value, :initial_margin, :maintenance_margin, :margin_ratio, keyword_init: true)

      # @param position [Position]
      # @param mark_price [Numeric]
      # @return [Result]
      def self.call(position:, mark_price:)
        qty = position.size.to_d.abs
        return zero_result if qty.zero?

        leverage = [position.leverage.to_d, 1.to_d].max
        position_value = qty * mark_price.to_d
        initial_margin = position_value / leverage
        maintenance_margin = position_value * maintenance_rate(position)

        margin_ratio = if initial_margin.zero?
                         0.to_d
                       else
                         maintenance_margin / initial_margin
                       end

        Result.new(
          position_value: position_value,
          initial_margin: initial_margin,
          maintenance_margin: maintenance_margin,
          margin_ratio: margin_ratio
        )
      end

      def self.maintenance_rate(_position)
        ENV.fetch("RISK_MAINTENANCE_MARGIN_RATE", "0.005").to_d
      end

      def self.zero_result
        Result.new(position_value: 0.to_d, initial_margin: 0.to_d, maintenance_margin: 0.to_d, margin_ratio: 0.to_d)
      end
    end
  end
end
