# frozen_string_literal: true

module Bot
  class ProductCache
    class MissingProductError < StandardError; end

    def initialize(symbols:, products:)
      @forward  = {}  # symbol → { product_id:, contract_value:, lot_size: }
      @inverse  = {}  # product_id → symbol

      symbols.each do |sym|
        product = products.find { |p| p.symbol == sym }
        raise MissingProductError, "Unknown symbol: #{sym}" unless product

        lot = product.respond_to?(:contract_lot_multiplier) ? product.contract_lot_multiplier.to_f : product.contract_value.to_f
        @forward[sym] = { product_id: product.id, contract_value: lot, lot_size: lot }
        @inverse[product.id] = sym
      end
    end

    def product_id_for(symbol)
      @forward.fetch(symbol) { raise MissingProductError, "Unknown symbol: #{symbol}" }[:product_id]
    end

    def contract_value_for(symbol)
      @forward.fetch(symbol) { raise MissingProductError, "Unknown symbol: #{symbol}" }[:contract_value]
    end

    def lot_size_for(symbol)
      @forward.fetch(symbol) { raise MissingProductError, "Unknown symbol: #{symbol}" }[:lot_size]
    end

    def symbol_for(product_id)     = @inverse[product_id]

    def known_symbol?(symbol)      = @forward.key?(symbol)

    def known_product_id?(product_id) = @inverse.key?(product_id)
  end
end
