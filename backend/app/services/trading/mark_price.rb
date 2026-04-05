# frozen_string_literal: true

module Trading
  # Mark price for PnL / liquidation; prefers explicit mark cache, then LTP.
  module MarkPrice
    module_function

    def for_symbol(symbol)
      sym = symbol.to_s
      Rails.cache.read("mark:#{sym}")&.to_d&.nonzero? ||
        Rails.cache.read("ltp:#{sym}")&.to_d&.nonzero?
    end

    # LTP chain for synthetic closes; matches +Trading::Dashboard::Snapshot#resolve_dashboard_mark_price+
    # (cache, PriceStore, paper Redis, catalog, then optional +entry_price+).
    #
    # @param fallback_entry_price [Boolean] when false, returns +nil+ if no live/catalog price exists
    #   (use for near-liquidation watchdog — entry must not stand in for mark).
    def for_synthetic_exit(position, fallback_entry_price: true)
      live_or_catalog_price(position) ||
        (fallback_entry_price ? position.entry_price.to_d : nil)
    end

    def live_or_catalog_price(position)
      sym = position.symbol.to_s

      from_cache(sym) ||
        from_price_store(sym) ||
        from_paper_redis_for_position(position) ||
        from_symbol_config(sym)
    end
    private_class_method :live_or_catalog_price

    # Paper LTP is keyed by Delta +product_id+. Rows often omit +product_id+; resolve it from +SymbolConfig+
    # so forced exits use the same live path as +Trading::Dashboard::Snapshot#resolve_dashboard_mark_price+.
    def from_paper_redis_for_position(position)
      pid = paper_product_id_for(position)
      return nil if pid.blank?

      positive_decimal(::PaperTrading::RedisStore.get_ltp(pid))
    end
    private_class_method :from_paper_redis_for_position

    def paper_product_id_for(position)
      position.product_id.presence ||
        SymbolConfig.find_by(symbol: position.symbol.to_s)&.product_id
    end
    private_class_method :paper_product_id_for

    def from_cache(sym)
      positive_decimal(Rails.cache.read("mark:#{sym}")) ||
        positive_decimal(Rails.cache.read("ltp:#{sym}"))
    end
    private_class_method :from_cache

    def from_price_store(sym)
      positive_decimal(Bot::Feed::PriceStore.new.get(sym))
    end
    private_class_method :from_price_store

    def from_symbol_config(sym)
      cfg = SymbolConfig.find_by(symbol: sym)
      return nil unless cfg

      positive_decimal(cfg.last_mark_price) || positive_decimal(cfg.last_close_price)
    end
    private_class_method :from_symbol_config

    def positive_decimal(value)
      return nil if value.nil?

      d = value.to_d
      d.positive? ? d : nil
    end
    private_class_method :positive_decimal
  end
end
