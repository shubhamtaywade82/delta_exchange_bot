# frozen_string_literal: true

module Trading
  module Risk
    # Ensures a hypothetical fill does not require more initial margin than +portfolio.available_balance+.
    class MarginAffordability
      EPSILON = BigDecimal("1e-6")

      HypotheticalFill = Struct.new(:quantity, :price, :filled_at, :id, :order_side, keyword_init: true) do
        def signed_quantity
          q = quantity.to_d
          order_side.to_s == "sell" ? -q : q
        end
      end

      class << self
        # @raise [Trading::RiskManager::RiskError] when incremental margin exceeds available cash
        def verify!(portfolio:, symbol:, order_side:, order_size:, fill_price:, position:, session:)
          portfolio.reload
          fill_price_d = fill_price.to_d
          return if fill_price_d <= 0 || order_size.to_d <= 0

          existing = Fill.joins(:order)
                         .where(orders: { portfolio_id: portfolio.id, symbol: symbol })
                         .includes(:order)
                         .to_a

          hypo = HypotheticalFill.new(
            quantity: order_size,
            price: fill_price_d,
            filled_at: Time.current + 1.second,
            id: 9_223_372_036_854_775_807,
            order_side: order_side.to_s
          )

          calc = Ledger::NetPositionCalculator.from_fills(existing + [hypo])
          lot_d = PositionLotSize.multiplier_for(position).to_d
          lev = effective_leverage(position, session)
          margin_after = margin_for_net(calc.signed_qty, calc.avg_entry, lot_d, lev)

          current_row = Position.active.find_by(portfolio_id: portfolio.id, symbol: symbol)
          margin_before = current_row&.margin&.to_d || 0.to_d

          incremental = margin_after - margin_before
          return if incremental <= portfolio.available_balance.to_d + EPSILON

          raise Trading::RiskManager::RiskError,
                "insufficient cash for margin: need #{incremental.round(2)} USD more initial margin " \
                "(available #{portfolio.available_balance.to_f.round(2)} USD)"
        end

        private

        def margin_for_net(signed_qty, avg_entry, lot_d, lev)
          q = signed_qty.to_d
          return 0.to_d if q.zero? || lot_d <= 0 || lev <= 0

          avg = avg_entry&.to_d
          return 0.to_d unless avg&.positive?

          (q.abs * lot_d * avg.abs) / lev
        end

        def effective_leverage(position, session)
          lev = position.leverage.to_d
          return lev if lev.positive?

          picked = Order.where(position_id: position.id)
                        .joins(:trading_session)
                        .limit(1)
                        .pick("trading_sessions.leverage")
          lev = picked.to_d
          return lev if lev.positive?

          slev = session&.leverage.to_d
          return slev if slev.positive?

          1.to_d
        end
      end
    end
  end
end
