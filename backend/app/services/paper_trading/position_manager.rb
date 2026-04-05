# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module PaperTrading
  class PositionManager
    InsufficientMarginError = Class.new(StandardError)
    Result = Struct.new(:action, :realized_pnl, :margin_delta, keyword_init: true)
    DEFAULT_MAINTENANCE_MARGIN_RATE = BigDecimal("0.005")
    DEFAULT_LIQUIDATION_FEE_RATE = BigDecimal("0.003")
    DEFAULT_LIQUIDATION_STEP_SIZE = 1
    DEFAULT_MARK_MAX_AGE_SECONDS = 2

    class << self
      def estimate_margin_inr(quantity:, price:, contract_value:, leverage:, usd_inr_rate:)
        margin_usd = estimate_margin_usd(
          quantity: quantity,
          price: price,
          contract_value: contract_value,
          leverage: leverage
        )
        (margin_usd * usd_inr_rate.to_d).round(2)
      end

      def estimate_margin_usd(quantity:, price:, contract_value:, leverage:)
        lev = [ leverage.to_i, 1 ].max.to_d
        (price.to_d * quantity.to_d * contract_value.to_d) / lev
      end
    end

    def initialize(wallet:, product:, usd_inr_rate: nil)
      @wallet = wallet
      @product = product
      @usd_inr_rate = (usd_inr_rate || Finance::UsdInrRate.current).to_d
    end

    # Applies one fill to paper ledger + positions atomically and idempotently for movement rows.
    def apply_fill(fill:, fill_side:, quantity:, price:, leverage: nil)
      raise InsufficientMarginError, "wallet is bankrupt; trading disabled" if @wallet.status == "bankrupt"
      return Result.new(action: :noop, realized_pnl: 0.to_d, margin_delta: 0.to_d) if fill_movement_applied?(fill)

      side = normalize_side(fill_side)
      quantity = Integer(quantity)
      raise ArgumentError, "quantity must be positive" unless quantity.positive?

      fill_price = price.to_d
      contract_value = @product.contract_value.to_d
      risk_unit = @product.risk_unit_per_contract.to_d
      fill_leverage = resolve_leverage(leverage)
      ensure_notional_cap!(incoming_qty: quantity, incoming_price: fill_price, side: side)

      result = nil

      ActiveRecord::Base.transaction do
        with_fill_advisory_lock(fill.id) do
          fill.with_lock do
            @wallet.with_lock do
              @wallet.recompute_from_ledger!
              position = PaperPosition.lock.find_by(
                paper_wallet_id: @wallet.id,
                paper_product_snapshot_id: @product.id
              )

              result =
                if position.nil? || position.net_quantity.zero?
                  open_position(side, quantity, fill_price, risk_unit, contract_value, fill, leverage: fill_leverage)
                elsif position.side == side
                  add_position(position, quantity, fill_price, contract_value, fill)
                else
                  close_and_maybe_flip(position, side, quantity, fill_price, risk_unit, contract_value, fill, flip_leverage: fill_leverage)
                end

              @wallet.recompute_from_ledger!
              liquidate_if_breached!
            end
            @wallet.recompute_from_ledger!
          end
        end
      end

      @wallet.reload
      result
    end

    private

    def fill_movement_applied?(fill)
      PaperWalletLedgerEntry.where(paper_wallet: @wallet, reference: fill)
                            .where(entry_type: %w[margin_reserved margin_released realized_pnl])
                            .exists?
    end

    def normalize_side(raw)
      case raw.to_s.downcase
      when "long", "buy" then "buy"
      when "short", "sell" then "sell"
      else
        raise ArgumentError, "invalid side: #{raw}"
      end
    end

    def resolve_leverage(explicit)
      explicit_lev = explicit.to_i
      return explicit_lev if explicit_lev.positive?

      product_lev = @product.default_leverage.to_i
      product_lev.positive? ? product_lev : 1
    end

    def to_inr(usd_amount)
      (usd_amount.to_d * @usd_inr_rate).round(2)
    end

    def record_fee!(fill, leg:, quantity:, price:)
      liquidity = fill.liquidity.presence || "taker"
      rate = Fees.effective_fee_rate(product: @product, liquidity: liquidity)
      notional = Fees.notional_usd(quantity: quantity, price: price, contract_value: @product.contract_value)
      fee_usd = Fees.fee_usd(notional_usd: notional, fee_rate: rate)
      fee_inr = Fees.fee_inr(fee_usd: fee_usd, usd_inr_rate: @usd_inr_rate)
      return if fee_inr.zero?

      write_ledger!("commission", :debit, fee_inr, fill, sub_type: "#{leg}_fee", meta: { "leg" => leg, "liquidity" => liquidity })
    end

    def open_position(side, quantity, price, risk_unit, contract_value, fill, leverage:)
      lev = resolve_leverage(leverage)
      margin_inr = margin_inr_for(quantity: quantity, price: price, contract_value: contract_value, leverage: lev)
      ensure_sufficient_margin!(required_margin_inr: margin_inr)

      write_ledger!("margin_reserved", :debit, margin_inr, fill, sub_type: "margin_lock")
      record_fee!(fill, leg: "entry", quantity: quantity, price: price)
      stamp_entry_fill!(fill, quantity: quantity, margin_inr: margin_inr)

      PaperPosition.create!(
        paper_wallet: @wallet,
        paper_product_snapshot: @product,
        side: side,
        net_quantity: quantity,
        avg_entry_price: price,
        risk_unit_per_contract: risk_unit,
        leverage: lev
      )

      Result.new(action: :opened, realized_pnl: 0.to_d, margin_delta: margin_inr / @usd_inr_rate)
    end

    def add_position(position, quantity, price, contract_value, fill)
      lev = [ position.leverage.to_i, 1 ].max
      margin_inr = margin_inr_for(quantity: quantity, price: price, contract_value: contract_value, leverage: lev)
      ensure_sufficient_margin!(required_margin_inr: margin_inr)

      prev_qty = position.net_quantity.to_d
      new_qty = prev_qty + quantity
      new_avg = ((prev_qty * position.avg_entry_price.to_d) + (quantity * price)) / new_qty

      write_ledger!("margin_reserved", :debit, margin_inr, fill, sub_type: "margin_lock")
      record_fee!(fill, leg: "entry", quantity: quantity, price: price)
      stamp_entry_fill!(fill, quantity: quantity, margin_inr: margin_inr)
      position.update!(net_quantity: new_qty.to_i, avg_entry_price: new_avg)

      Result.new(action: :added, realized_pnl: 0.to_d, margin_delta: margin_inr / @usd_inr_rate)
    end

    def close_and_maybe_flip(position, incoming_side, quantity, price, risk_unit, contract_value, fill, flip_leverage:)
      pos_qty = position.net_quantity
      close_qty = [ pos_qty, quantity ].min
      excess = quantity - close_qty

      exit_fee_usd = compute_exit_fee_usd(fill: fill, close_qty: close_qty, price: price)
      gross_pnl_usd, net_pnl = compute_close_pnl(position, close_qty, price, risk_unit, exit_fee_usd)
      released_inr = release_close_margin_from_entry_fills!(position_side: position.side, close_qty: close_qty)

      persist_close!(fill, position, pos_qty - close_qty, close_qty, price, released_inr, gross_pnl_usd)

      flip_reserve_usd, action = attempt_flip(excess, incoming_side, price, risk_unit, contract_value, fill, flip_leverage)
      released_usd = @usd_inr_rate.positive? ? (released_inr / @usd_inr_rate) : 0.to_d
      Result.new(action: action, realized_pnl: net_pnl, margin_delta: flip_reserve_usd - released_usd)
    end

    def compute_exit_fee_usd(fill:, close_qty:, price:)
      rate = Fees.effective_fee_rate(product: @product, liquidity: fill.liquidity.presence || "taker")
      notional = Fees.notional_usd(quantity: close_qty, price: price, contract_value: @product.contract_value)
      Fees.fee_usd(notional_usd: notional, fee_rate: rate)
    end

    def compute_close_pnl(position, close_qty, price, risk_unit, exit_fee_usd)
      pnl_side = position.side == "buy" ? :buy : :sell
      gross = PnlCalculator.call(
        side: pnl_side,
        entry_price: position.avg_entry_price,
        exit_price: price,
        quantity: close_qty,
        risk_unit_value: risk_unit,
        fees: 0.to_d
      )
      net = PnlCalculator.call(
        side: pnl_side,
        entry_price: position.avg_entry_price,
        exit_price: price,
        quantity: close_qty,
        risk_unit_value: risk_unit,
        fees: exit_fee_usd
      )
      [ gross[:gross_pnl], net[:net_pnl] ]
    end

    def persist_close!(fill, position, remaining_qty, close_qty, price, released_inr, gross_pnl_usd)
      record_fee!(fill, leg: "exit", quantity: close_qty, price: price)
      write_ledger!("margin_released", :credit, released_inr, fill, sub_type: "margin_release")
      record_realized_pnl!(fill, gross_pnl_usd)

      if remaining_qty.zero?
        position.destroy!
      else
        position.update!(net_quantity: remaining_qty)
      end
    end

    def record_realized_pnl!(fill, gross_pnl_usd)
      amount = to_inr(gross_pnl_usd.abs)
      if gross_pnl_usd >= 0
        write_ledger!("realized_pnl", :credit, amount, fill, sub_type: "pnl")
      else
        write_ledger!("realized_pnl", :debit, amount, fill, sub_type: "pnl")
      end
    end

    def attempt_flip(excess, incoming_side, price, risk_unit, contract_value, fill, flip_leverage)
      return [ 0.to_d, :closed ] unless excess.positive?

      flip_lev = resolve_leverage(flip_leverage)
      reserve_usd = ActiveRecord::Base.transaction(requires_new: true) do
        open_after_flip(incoming_side, excess, price, risk_unit, contract_value, fill, leverage: flip_lev)
      end
      [ reserve_usd, :flipped ]
    rescue InsufficientMarginError, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[PaperTrading::PositionManager] flip skipped after close: #{e.message}")
      [ 0.to_d, :closed ]
    end

    def open_after_flip(side, quantity, price, risk_unit, contract_value, fill, leverage:)
      lev = resolve_leverage(leverage)
      margin_inr = margin_inr_for(quantity: quantity, price: price, contract_value: contract_value, leverage: lev)
      ensure_sufficient_margin!(required_margin_inr: margin_inr)

      write_ledger!("margin_reserved", :debit, margin_inr, fill, sub_type: "margin_lock")
      record_fee!(fill, leg: "entry", quantity: quantity, price: price)
      stamp_entry_fill!(fill, quantity: quantity, margin_inr: margin_inr)

      PaperPosition.create!(
        paper_wallet: @wallet,
        paper_product_snapshot: @product,
        side: side,
        net_quantity: quantity,
        avg_entry_price: price,
        risk_unit_per_contract: risk_unit,
        leverage: lev
      )
      margin_inr / @usd_inr_rate
    end

    def ensure_sufficient_margin!(required_margin_inr:)
      available = @wallet.available_inr.to_d
      required = required_margin_inr.to_d.round(2)
      return if available >= required

      raise InsufficientMarginError,
            "insufficient paper margin: required_inr=#{required.to_s("F")} available_inr=#{available.to_s("F")}"
    end

    def ensure_notional_cap!(incoming_qty:, incoming_price:, side:)
      max_leverage_cap = ENV["PAPER_MAX_LEVERAGE_CAP"]&.to_d
      max_leverage_cap = 10.to_d if max_leverage_cap.nil? || max_leverage_cap <= 0
      cap_usd = (@wallet.balance_inr.to_d / @usd_inr_rate) * max_leverage_cap

      existing_notional = open_positions.sum do |position|
        position.net_quantity.to_d * @product.contract_value.to_d * incoming_price.to_d
      end
      incoming_notional = incoming_qty.to_d * @product.contract_value.to_d * incoming_price.to_d
      total = side == "buy" || side == "sell" ? (existing_notional + incoming_notional) : existing_notional
      return if total <= cap_usd

      raise InsufficientMarginError, "notional cap exceeded: required_usd=#{total.to_s("F")} cap_usd=#{cap_usd.to_s("F")}"
    end

    def margin_inr_for(quantity:, price:, contract_value:, leverage:)
      self.class.estimate_margin_inr(
        quantity: quantity,
        price: price,
        contract_value: contract_value,
        leverage: leverage,
        usd_inr_rate: @usd_inr_rate
      )
    end

    def stamp_entry_fill!(fill, quantity:, margin_inr:)
      fill.update!(
        filled_qty: quantity,
        closed_qty: 0,
        margin_inr_per_fill: margin_inr
      )
    end

    def entry_fills_for(position_side:)
      PaperFill.joins(:paper_order)
              .where(paper_orders: {
                paper_wallet_id: @wallet.id,
                paper_product_snapshot_id: @product.id,
                side: position_side
              })
              .where("paper_fills.filled_qty > paper_fills.closed_qty")
              .order(:filled_at, :id)
              .lock
    end

    def liquidate_if_breached!
      mark_price = liquidation_mark_price
      return if mark_price.nil?

      maintenance_margin = maintenance_margin_inr(mark_price: mark_price)
      @wallet.refresh_snapshot!(ltp_map: { @product.product_id => mark_price })
      return unless @wallet.equity_inr.to_d < maintenance_margin

      open_positions.each { |position| liquidate_incrementally!(position, mark_price: mark_price) }
    end

    def maintenance_margin_inr(mark_price:)
      rate = maintenance_margin_rate

      open_positions.sum do |position|
        notional_usd = position.net_quantity.to_d * @product.contract_value.to_d * mark_price.to_d
        (notional_usd * rate * @usd_inr_rate).round(2)
      end
    end

    def open_positions
      PaperPosition.lock.where(paper_wallet_id: @wallet.id, paper_product_snapshot_id: @product.id)
    end

    def liquidate_incrementally!(position, mark_price:)
      step_index = 0

      while position.net_quantity.positive? && !safe_after_liquidation?(mark_price: mark_price)
        step_index += 1
        step_qty = [ liquidation_quantity_for(position: position, mark_price: mark_price), position.net_quantity ].min
        apply_liquidation_step!(position: position, mark_price: mark_price, quantity: step_qty, step_index: step_index)
        position.reload
      end
    end

    def apply_liquidation_step!(position:, mark_price:, quantity:, step_index:)
      reference_fill = position_related_fill(position)
      consumed_lots = consume_entry_fills!(position_side: position.side, close_qty: quantity)
      released_inr = consumed_lots.sum { |lot| lot[:released_margin_inr] }.round(2)
      liquidation_ref = liquidation_external_ref(reference_fill: reference_fill, step_index: step_index)
      write_ledger!("margin_released", :credit, released_inr, reference_fill, external_ref_override: liquidation_ref,
                    sub_type: "liquidation_margin_release", meta: { "liquidation" => true, "step" => step_index })
      write_liquidation_fee!(position: position, mark_price: mark_price, quantity: quantity,
                             reference_fill: reference_fill, step_index: step_index, liquidation_ref: liquidation_ref)
      write_liquidation_pnl!(position: position, mark_price: mark_price, consumed_lots: consumed_lots,
                             reference_fill: reference_fill, step_index: step_index, liquidation_ref: liquidation_ref)

      remaining = position.net_quantity - quantity
      if remaining.positive?
        position.update!(net_quantity: remaining)
      else
        position.destroy!
      end
      @wallet.recompute_from_ledger!
      @wallet.refresh_snapshot!(ltp_map: { @product.product_id => mark_price })
      clamp_wallet_equity_floor!
    end

    def position_related_fill(position)
      PaperFill.joins(:paper_order)
              .where(paper_orders: {
                paper_wallet_id: @wallet.id,
                paper_product_snapshot_id: position.paper_product_snapshot_id
              }).order(id: :desc).first
    end

    def write_ledger!(entry_type, direction, amount_inr, reference, sub_type:, external_ref_override: nil, meta: {})
      attrs = {
        paper_wallet: @wallet,
        entry_type: entry_type.to_s,
        external_ref: external_ref_override || ledger_external_ref(reference: reference),
        sub_type: sub_type.to_s,
        direction: direction.to_s,
        amount_inr: amount_inr.round(2),
        reference: reference,
        meta: meta.stringify_keys
      }

      PaperWalletLedgerEntry.find_or_create_by!(
        paper_wallet: attrs[:paper_wallet],
        entry_type: attrs[:entry_type],
        external_ref: attrs[:external_ref],
        sub_type: attrs[:sub_type]
      ) do |entry|
        entry.direction = attrs[:direction]
        entry.amount_inr = attrs[:amount_inr]
        entry.reference = attrs[:reference]
        entry.meta = attrs[:meta]
      end
    end

    def maintenance_margin_rate
      value = @product.raw_metadata&.dig("maintenance_margin")&.to_d
      value ||= ENV["PAPER_MAINTENANCE_MARGIN_RATE"]&.to_d
      value&.positive? ? value : DEFAULT_MAINTENANCE_MARGIN_RATE
    end

    def liquidation_fee_rate
      value = @product.raw_metadata&.dig("liquidation_fee_rate")&.to_d
      value ||= ENV["PAPER_LIQUIDATION_FEE_RATE"]&.to_d
      value&.positive? ? value : DEFAULT_LIQUIDATION_FEE_RATE
    end

    def write_liquidation_fee!(position:, mark_price:, quantity:, reference_fill:, step_index:, liquidation_ref:)
      notional = quantity.to_d * @product.contract_value.to_d * mark_price.to_d
      fee_inr = to_inr(notional * liquidation_fee_rate)
      write_ledger!("commission", :debit, fee_inr, reference_fill, external_ref_override: liquidation_ref,
                    sub_type: "liquidation_fee",
                    meta: { "leg" => "liquidation", "liquidity" => "taker", "step" => step_index })
    end

    def write_liquidation_pnl!(position:, mark_price:, consumed_lots:, reference_fill:, step_index:, liquidation_ref:)
      gross = consumed_lots.sum do |lot|
        lot_side_multiplier(position.side) * lot[:quantity].to_d * @product.contract_value.to_d * (mark_price.to_d - lot[:entry_price].to_d)
      end

      amount_inr = to_inr(gross.abs)
      if gross >= 0
        write_ledger!("realized_pnl", :credit, amount_inr, reference_fill, external_ref_override: liquidation_ref,
                      sub_type: "liquidation_pnl",
                      meta: { "liquidation" => true, "step" => step_index })
      else
        write_ledger!("realized_pnl", :debit, amount_inr, reference_fill, external_ref_override: liquidation_ref,
                      sub_type: "liquidation_pnl",
                      meta: { "liquidation" => true, "step" => step_index })
      end
    end

    def liquidation_mark_price
      cache_key = "mark_price:#{@product.symbol}"
      cached = Rails.cache.read(cache_key)
      price, timestamp = extract_mark_payload(cached)
      return price if price&.positive? && mark_fresh?(timestamp)

      Rails.logger.warn("[PaperTrading::PositionManager] skip liquidation check: mark price missing symbol=#{@product.symbol}")
      nil
    end

    def safe_after_liquidation?(mark_price:)
      @wallet.refresh_snapshot!(ltp_map: { @product.product_id => mark_price })
      @wallet.equity_inr.to_d >= maintenance_margin_inr(mark_price: mark_price)
    end

    def liquidation_step_size
      configured = @product.raw_metadata&.dig("liquidation_step_size")&.to_i
      configured = ENV["PAPER_LIQUIDATION_STEP_SIZE"]&.to_i if configured.nil? || configured <= 0
      configured&.positive? ? configured : DEFAULT_LIQUIDATION_STEP_SIZE
    end

    def liquidation_quantity_for(position:, mark_price:)
      current_equity_usd = @wallet.equity_inr.to_d / @usd_inr_rate
      required_equity_usd = maintenance_margin_inr(mark_price: mark_price) / @usd_inr_rate
      deficit = required_equity_usd - current_equity_usd
      return liquidation_step_size if deficit <= 0

      loss_per_contract = @product.contract_value.to_d * (position.avg_entry_price.to_d - mark_price.to_d).abs
      return liquidation_step_size if loss_per_contract <= 0

      [ (deficit / loss_per_contract).ceil, 1 ].max
    end

    def with_fill_advisory_lock(fill_id)
      key = Integer(fill_id)
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{key})")
      yield
    end

    def consume_entry_fills!(position_side:, close_qty:)
      remaining_to_close = close_qty.to_i
      consumed = []

      entry_fills_for(position_side: position_side).each do |entry_fill|
        break unless remaining_to_close.positive?

        open_qty = entry_fill.filled_qty - entry_fill.closed_qty
        next unless open_qty.positive?

        matched_qty = [ remaining_to_close, open_qty ].min
        release_inr = (entry_fill.margin_inr_per_fill.to_d * matched_qty.to_d / entry_fill.filled_qty.to_d).round(2)

        entry_fill.update!(closed_qty: entry_fill.closed_qty + matched_qty)
        consumed << { entry_price: entry_fill.price.to_d, quantity: matched_qty, released_margin_inr: release_inr }
        remaining_to_close -= matched_qty
      end

      raise StandardError, "entry fill inventory underflow" if remaining_to_close.positive?

      consumed
    end

    def release_close_margin_from_entry_fills!(position_side:, close_qty:)
      consume_entry_fills!(position_side: position_side, close_qty: close_qty).sum { |lot| lot[:released_margin_inr] }.round(2)
    end

    def lot_side_multiplier(side)
      side == "buy" ? 1.to_d : -1.to_d
    end

    def liquidation_external_ref(reference_fill:, step_index:)
      base = ledger_external_ref(reference: reference_fill) || "liquidation:wallet:#{@wallet.id}:product:#{@product.id}"
      "#{base}:liquidation_step_#{step_index}"
    end

    def extract_mark_payload(payload)
      case payload
      when Array
        [ payload[0]&.to_d, payload[1] ]
      else
        [ payload&.to_d, Time.current ]
      end
    end

    def mark_fresh?(timestamp)
      ts = timestamp.is_a?(Time) ? timestamp : Time.zone.parse(timestamp.to_s)
      return false if ts.nil?

      Time.current - ts <= mark_max_age_seconds
    rescue StandardError
      false
    end

    def mark_max_age_seconds
      configured = ENV["PAPER_MARK_MAX_AGE_SECONDS"]&.to_i
      configured&.positive? ? configured : DEFAULT_MARK_MAX_AGE_SECONDS
    end

    def clamp_wallet_equity_floor!
      return unless @wallet.equity_inr.to_d.negative?

      @wallet.update_columns(balance_inr: 0, available_inr: 0, equity_inr: 0, used_margin_inr: 0, status: "bankrupt")
    end

    def ledger_external_ref(reference:)
      return nil unless reference&.respond_to?(:id)

      "#{reference.class.name}:#{reference.id}"
    end
  end
end
