# frozen_string_literal: true

module Bot
  class ProductCache
    class MissingProductError < StandardError; end

    def initialize(symbols:, products:)
      @forward  = {}  # symbol → { product_id:, contract_value: }
      @inverse  = {}  # product_id → symbol

      symbols.each do |sym|
        product = products.find { |p| p.symbol == sym }
        raise MissingProductError, "Product not found for symbol: #{sym}" unless product

        @forward[sym] = { product_id: product.id, contract_value: product.contract_value.to_f }
        @inverse[product.id] = sym
      end
    end

    def product_id_for(symbol)     = @forward.fetch(symbol)[:product_id]
    def contract_value_for(symbol) = @forward.fetch(symbol)[:contract_value]
    def symbol_for(product_id)     = @inverse[product_id]
    def known_symbol?(symbol)      = @forward.key?(symbol)
  end
end
