# frozen_string_literal: true

module Trading
  module Risk
    # Per-contract multiplier from Delta product metadata: `lot_size` when present, else
    # `contract_value` (see https://docs.delta.exchange/ GET /v2/products). Order `size` is
    # in contracts; PnL/notional scale as `size * multiplier` for vanilla linear instruments.
    module PositionLotSize
      CACHE_TTL = 1.hour

      module_function

      def multiplier_for(position)
        persisted = position.contract_value.to_f
        return persisted if persisted.positive?

        from_exchange(position.symbol.to_s)
      end

      def from_exchange(symbol)
        return 1.0 if symbol.blank?
        return 1.0 if Rails.env.test?

        Rails.cache.fetch("delta:product:lot_multiplier:#{symbol}", expires_in: CACHE_TTL) do
          DeltaExchange::Models::Product.find(symbol).contract_lot_multiplier.to_f
        end
      rescue StandardError => e
        Rails.logger.warn("[PositionLotSize] #{symbol}: #{e.message}")
        1.0
      end
    end
  end
end
