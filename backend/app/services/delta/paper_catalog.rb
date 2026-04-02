# frozen_string_literal: true

module Delta
  # Syncs Delta Exchange public product + ticker data into PaperProductSnapshot and Redis (paper broker).
  class PaperCatalog
    def self.sync_products!(symbols: nil)
      list = Array(symbols).map(&:to_s).presence
      list ||= SymbolConfig.where(enabled: true).order(:symbol).pluck(:symbol)
      return 0 if list.empty?

      count = 0
      list.each do |sym|
        product = DeltaExchange::Models::Product.find(sym)
        attrs = build_snapshot_attrs(product)
        PaperProductSnapshot.upsert(attrs, unique_by: :product_id)
        count += 1
      rescue StandardError => e
        Rails.logger.warn("[Delta::PaperCatalog] product sync failed symbol=#{sym}: #{e.message}")
      end
      count
    end

    def self.sync_tickers!(symbols: nil)
      list = Array(symbols).map(&:to_s).presence
      tickers =
        if list.present?
          list.filter_map do |sym|
            DeltaExchange::Models::Ticker.find(sym)
          rescue StandardError
            nil
          end
        else
          DeltaExchange::Models::Ticker.all({})
        end

      tickers.each do |t|
        sym = t.symbol.to_s
        snap = PaperProductSnapshot.find_by(symbol: sym)
        next unless snap

        mark = decimal_or_nil(t.mark_price)
        close = decimal_or_nil(t.close)
        snap.update_columns(
          mark_price: mark,
          close_price: close,
          updated_at: Time.current
        )
        price = (mark.present? && mark.to_d.positive?) ? mark.to_d : close&.to_d
        next unless price&.positive?

        PaperTrading::RedisStore.set_ltp(snap.product_id, price, symbol: sym)
        PaperTrading::RedisStore.set_product_json(snap.product_id, { symbol: sym, mark_price: mark&.to_s("F"), close: close&.to_s("F") })
      end
      tickers.size
    end

    def self.build_snapshot_attrs(product)
      v = PaperTrading::Valuation.from_delta_product(product)
      now = Time.current
      {
        product_id: product.id.to_i,
        symbol: product.symbol.to_s,
        contract_type: product.contract_type,
        settling_asset: product.respond_to?(:settlement_asset_symbol) ? product.settlement_asset_symbol : nil,
        notional_type: product.respond_to?(:notional_type) ? product.notional_type : nil,
        contract_value: product.contract_value.to_s.to_d,
        risk_unit_per_contract: v[:risk_unit_per_contract].to_d,
        valuation_strategy: v[:valuation_strategy],
        tick_size: product.tick_size.to_s.to_d,
        position_size_limit: product.respond_to?(:position_size_limit) ? product.position_size_limit&.to_i : nil,
        mark_price: nil,
        close_price: nil,
        raw_metadata: product.respond_to?(:raw_attributes) ? product.raw_attributes : {},
        created_at: now,
        updated_at: now
      }
    end

    def self.decimal_or_nil(val)
      return nil if val.blank?

      val.to_d
    end
  end
end
