# frozen_string_literal: true

module Trading
  module Risk
    # Executor applies hard risk actions (forced exit / defensive tightening).
    class Executor
      # @param position [Position]
      # @param signal [Symbol]
      # @param mark_price [Numeric]
      # @return [void]
      def self.handle!(position:, signal:, mark_price:)
        case signal
        when :liquidation
          close_position!(position, "LIQUIDATION_EXIT", mark_price: mark_price)
        when :danger
          tighten_sl!(position, mark_price: mark_price)
        end
      end

      def self.close_position!(position, reason, mark_price:)
        OrdersRepository.close_position(
          position_id: position.id,
          reason: reason,
          mark_price: mark_price
        )
      end

      def self.tighten_sl!(position, mark_price:)
        mark = mark_price.to_d
        return if mark <= 0

        buffer = ENV.fetch("RISK_DANGER_STOP_BUFFER", "0.98").to_d
        stop = if position.side.to_s.in?(%w[long buy])
                 mark * buffer
               else
                 mark / buffer
               end

        position.update!(stop_price: stop)
      end
    end
  end
end
