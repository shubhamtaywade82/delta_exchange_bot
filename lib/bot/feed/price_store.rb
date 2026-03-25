# frozen_string_literal: true

module Bot
  module Feed
    class PriceStore
      def initialize
        @prices = {}
        @mutex  = Mutex.new
      end

      def update(symbol, price)
        @mutex.synchronize { @prices[symbol] = price.to_f }
      end

      def get(symbol)
        @mutex.synchronize { @prices[symbol] }
      end
    end
  end
end
