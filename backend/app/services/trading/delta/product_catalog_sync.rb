# frozen_string_literal: true

module Trading
  module Delta
    # Idempotent refresh of SymbolConfig from Delta GET /v2/products and tickers (via gem models).
    class ProductCatalogSync
      def self.sync_all!(symbols: nil)
        scope = SymbolConfig.where(enabled: true)
        scope = scope.where(symbol: symbols) if symbols.present?

        ok = 0
        scope.find_each { |config| ok += 1 if sync_one!(config) }
        ok
      end

      def self.sync_one!(config)
        sym = config.symbol.to_s.strip
        return false if sym.blank?

        product = DeltaExchange::Models::Product.find(sym)
        ticker = DeltaExchange::Models::Ticker.find(sym)

        mult = product.contract_lot_multiplier
        meta = (config.metadata || {}).deep_stringify_keys.merge(
          "contract_lot_multiplier" => mult.to_s("F"),
          "contract_value" => product.contract_value.to_s.presence,
          "lot_size" => product.lot_size.to_s.presence,
          "delta_product_id" => product.id.to_s
        )

        pid = Integer(product.id.to_s) rescue nil

        attrs = {
          tick_size: decimal_or_nil(product.tick_size),
          contract_type: product.contract_type.to_s.presence,
          metadata: meta,
          last_mark_price: decimal_or_nil(ticker.mark_price),
          last_close_price: decimal_or_nil(ticker.close),
          fetched_at: Time.current
        }
        attrs[:product_id] = pid if pid&.positive?

        config.update!(attrs)
        true
      rescue StandardError => e
        Rails.logger.warn("[ProductCatalogSync] #{sym}: #{e.message}")
        false
      end

      def self.decimal_or_nil(raw)
        return nil if raw.blank?

        BigDecimal(raw.to_s)
      end
      private_class_method :decimal_or_nil
    end
  end
end
