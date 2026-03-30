# frozen_string_literal: true

module Trading
  module Microstructure
    # LatencySignal detects imminent move setups from spread + imbalance.
    class LatencySignal
      # @param book [Trading::Orderbook::Book]
      # @return [Symbol]
      def self.detect(book)
        imbalance = Imbalance.calculate(book)
        spread = book.spread.to_f

        return :none if spread < ENV.fetch("MICROSTRUCTURE_MIN_SPREAD", "0.5").to_f

        if imbalance > 0.6
          :buy_before_move
        elsif imbalance < -0.6
          :sell_before_move
        else
          :none
        end
      end
    end
  end
end
