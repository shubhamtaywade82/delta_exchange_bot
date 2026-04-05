# frozen_string_literal: true

module Trading
  # Recomputes net position from all fills for (portfolio, symbol); updates wallet-related fields.
  class PositionRecalculator
    MAX_RETRIES = 3
    # Weighted-average entry from fills can carry huge fractional tails; cap for storage and UI.
    AVG_ENTRY_DECIMALS = 8

    def self.call(position_id)
      new(position_id).call
    end

    def initialize(position_id)
      @position_id = position_id
    end

    # @return [Position]
    def call
      retries = 0

      begin
        ActiveRecord::Base.transaction(isolation: :repeatable_read) do
          position = Position.lock.find(@position_id)
          lot_d = Trading::Risk::PositionLotSize.multiplier_for(position).to_d

          fills = load_fills_with_orders(position)

          calc = Trading::Ledger::NetPositionCalculator.from_fills(fills, lot_multiplier: lot_d)
          q = calc.signed_qty

          next_state = derive_status(position, q, fills)
          mark = Trading::MarkPrice.for_symbol(position.symbol) || calc.avg_entry

          attrs = base_attrs(q, calc, lot_d, next_state, position, mark)
          merge_trailing_stop!(attrs, position, attrs[:entry_price]) if q.nonzero?

          position.update!(attrs)

          position
        end
      rescue ActiveRecord::StaleObjectError, ActiveRecord::SerializationFailure => e
        retries += 1
        raise if retries >= MAX_RETRIES

        sleep(0.05 * retries) if e.is_a?(ActiveRecord::SerializationFailure)
        retry
      end
    end

    private

    # Join selects matching fill ids; load orders in one extra query and attach without +preload+ so Bullet
    # does not treat this as an unused +includes+ (it misses +NetPositionCalculator+’s use of +order+).
    def load_fills_with_orders(position)
      fill_ids = Fill.joins(:order)
                     .where(orders: { portfolio_id: position.portfolio_id, symbol: position.symbol })
                     .distinct
                     .pluck(:id)
      return [] if fill_ids.empty?

      fills = Fill.where(id: fill_ids).to_a
      order_ids = fills.map(&:order_id).uniq
      orders_by_id = Order.where(id: order_ids).index_by(&:id)
      fills.each do |fill|
        assoc = fill.association(:order)
        assoc.target = orders_by_id[fill.order_id]
        assoc.loaded!
      end
      fills
    end

    def base_attrs(q, calc, lot_d, next_state, position, mark)
      if q.zero?
        return {
          size: 0,
          side: position.side,
          entry_price: nil,
          margin: nil,
          unrealized_pnl_usd: 0,
          status: next_state,
          needs_reconciliation: false
        }
      end

      avg = calc.avg_entry&.round(AVG_ENTRY_DECIMALS)
      lev = effective_leverage(position)
      margin = if lev.positive? && lot_d.positive? && avg.present?
                 (q.abs * lot_d * avg.abs) / lev
      end

      side = q.positive? ? "long" : "short"
      position.assign_attributes(size: q.abs, side: side, entry_price: avg, margin: margin)

      unrealized = Trading::Risk::PositionRisk.call(position: position, mark_price: mark).unrealized_pnl

      attrs = {
        size: q.abs,
        side: side,
        entry_price: avg,
        margin: margin,
        leverage: lev.to_i,
        unrealized_pnl_usd: unrealized,
        pnl_usd: nil,
        status: next_state,
        needs_reconciliation: false
      }

      attrs[:contract_value] = lot_d if lot_d.positive? && (position.contract_value.blank? || position.contract_value.to_f.zero?)
      attrs
    end

    def derive_status(position, signed_qty, fills)
      pending_orders = Order.where(portfolio_id: position.portfolio_id, symbol: position.symbol)
                            .where(status: %w[created submitted partially_filled])

      if signed_qty.zero?
        return "entry_pending" if pending_orders.exists?

        return fills.any? ? "closed" : "init"
      end

      pending_orders.exists? ? "partially_filled" : "filled"
    end

    # Prefer +trading_sessions.leverage+ from the position's orders (execution truth). A stale +positions.leverage+
    # of 1 would otherwise force initial margin = full notional and blow past portfolio +balance+ in the UI.
    def effective_leverage(position)
      session_lev = Order.where(position_id: position.id)
                         .joins(:trading_session)
                         .order(:id)
                         .limit(1)
                         .pick("trading_sessions.leverage")
      if session_lev.present? && session_lev.to_i.positive?
        return BigDecimal(session_lev.to_s)
      end

      pos_lev = position.leverage
      if pos_lev.present? && pos_lev.to_i.positive?
        return BigDecimal(pos_lev.to_s)
      end

      sym_lev = SymbolConfig.find_by(symbol: position.symbol.to_s)&.leverage
      if sym_lev.present? && sym_lev.to_i.positive?
        return BigDecimal(sym_lev.to_s)
      end

      BigDecimal("1")
    end

    # +strategy.trailing_stop_pct+ is percent points (e.g. 1.5 => 1.5% distance to initial stop).
    def merge_trailing_stop!(attrs, position, avg_entry)
      status = attrs[:status].to_s
      return unless %w[filled open partially_filled].include?(status)
      return if position.trail_pct.present?

      avg = avg_entry&.to_d
      return unless avg&.positive?

      trail = trailing_stop_pct_decimal
      trail_frac = trail / BigDecimal("100")
      side = attrs[:side].to_s
      peak = avg
      stop = if side.in?(%w[long buy])
               avg * (BigDecimal("1") - trail_frac)
      else
               avg * (BigDecimal("1") + trail_frac)
      end

      attrs[:trail_pct] = trail
      attrs[:peak_price] = peak
      attrs[:stop_price] = stop
    end

    def trailing_stop_pct_decimal
      BigDecimal(Bot::Config.load.trailing_stop_pct.to_s)
    rescue Bot::Config::ValidationError
      BigDecimal("1.5")
    end
  end
end
