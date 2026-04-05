# frozen_string_literal: true

module PaperTrading
  # Backward-compatible wrapper. Use FillApplier for new code.
  class FillApplicator
    def initialize(order:, wallet:, product:)
      @applier = FillApplier.new(order: order, wallet: wallet, product: product)
    end

    def call(price:, size:, leverage: nil, liquidity: :taker)
      @applier.call(price: price, size: size, leverage: leverage, liquidity: liquidity)
    end
  end
end
