# frozen_string_literal: true

module Trading
  module Microstructure
    # SignalEngine converts microstructure imbalance into directional intents.
    class SignalEngine
      THRESHOLD = ENV.fetch("MICROSTRUCTURE_IMBALANCE_THRESHOLD", "0.2").to_f

      # @param book [Trading::Orderbook::Book]
      # @return [Symbol]
      def self.call(book)
        imbalance = Imbalance.calculate(book)

        if imbalance > THRESHOLD
          :long
        elsif imbalance < -THRESHOLD
          :short
        else
          :neutral
        end
      end
    end
  end
end
