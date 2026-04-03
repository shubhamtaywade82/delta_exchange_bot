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
      sym = position.symbol.to_s

      %W[mark:#{sym} ltp:#{sym}].each do |key|
        d = positive_decimal(Rails.cache.read(key))
        return d if d
      end

      d = positive_decimal(Bot::Feed::PriceStore.new.get(sym))
      return d if d

      if position.product_id.present?
        pr = ::PaperTrading::RedisStore.get_ltp(position.product_id)
        d = positive_decimal(pr)
        return d if d
      end

      cfg = SymbolConfig.find_by(symbol: sym)
      if cfg
        d = positive_decimal(cfg.last_mark_price)
        return d if d
        d = positive_decimal(cfg.last_close_price)
        return d if d
      end

      return nil unless fallback_entry_price

      position.entry_price.to_d
    end

    def positive_decimal(value)
      return nil if value.nil?

      d = value.to_d
      d.positive? ? d : nil
    end
    private_class_method :positive_decimal
  end
end
