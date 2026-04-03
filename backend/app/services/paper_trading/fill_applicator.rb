# frozen_string_literal: true

module PaperTrading
  # Creates a fill and applies it to positions + ledger inside the current DB transaction.
  class FillApplicator
    def initialize(order:, wallet:, product:)
      @order = order
      @wallet = wallet
      @product = product
    end

    def call(price:, size:, leverage: nil)
      price = price.to_d
      size = Integer(size)

      fill = @order.paper_fills.create!(
        size: size,
        price: price,
        filled_at: Time.current
      )

      manager = PositionManager.new(wallet: @wallet, product: @product)
      manager.apply_fill(
        fill: fill,
        fill_side: @order.side,
        quantity: size,
        price: price,
        leverage: leverage
      )
    end
  end
end
