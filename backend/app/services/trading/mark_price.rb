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
  end
end
