# frozen_string_literal: true

module Trading
  module Features
    # Extractor derives deterministic microstructure features from book and recent trades.
    class Extractor
      # @param book [Trading::Orderbook::Book]
      # @param trades [Array<Hash, Fill>]
      # @return [Hash]
      def self.call(book:, trades:)
        {
          spread: book.spread.to_f,
          imbalance: Trading::Microstructure::Imbalance.calculate(book),
          volatility: calc_volatility(trades),
          trade_intensity: trades.size,
          momentum: calc_momentum(trades)
        }
      end

      def self.calc_volatility(trades)
        prices = trades.map { |t| extract_price(t) }.compact
        return 0.0 if prices.size < 2

        mean = prices.sum / prices.size.to_f
        variance = prices.sum { |price| (price - mean)**2 } / prices.size.to_f
        Math.sqrt(variance)
      end

      def self.calc_momentum(trades)
        prices = trades.map { |t| extract_price(t) }.compact
        return 0.0 if prices.size < 2

        prices.last - prices.first
      end

      def self.extract_price(trade)
        if trade.respond_to?(:price)
          trade.price.to_f
        elsif trade.is_a?(Hash)
          trade[:price]&.to_f || trade["price"]&.to_f
        end
      end
    end
  end
end
