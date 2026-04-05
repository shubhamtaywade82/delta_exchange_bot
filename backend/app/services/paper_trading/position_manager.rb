# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module PaperTrading
  class PositionManager
    InsufficientMarginError = Class.new(StandardError)
    Result = Struct.new(:action, :realized_pnl, :margin_delta, keyword_init: true)

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
      return Result.new(action: :noop, realized_pnl: 0.to_d, margin_delta: 0.to_d) if fill_movement_applied?(fill)

      side = normalize_side(fill_side)
      quantity = Integer(quantity)
      raise ArgumentError, "quantity must be positive" unless quantity.positive?

      price = price.to_d
      risk_unit = @product.risk_unit_per_contract.to_d
      contract_value = @product.contract_value.to_d
      fill_leverage = resolve_leverage(leverage)

      position = nil
      result = nil

      ActiveRecord::Base.transaction do
        @wallet.with_lock do
          @wallet.recompute_from_ledger!
          position = PaperPosition.lock.find_by(
            paper_wallet_id: @wallet.id,
            paper_product_snapshot_id: @product.id
          )

          result =
            if position.nil? || position.net_quantity.zero?
              open_position(side, quantity, price, risk_unit, contract_value, fill, leverage: fill_leverage)
            elsif position.side == side
              add_position(position, quantity, price, contract_value, fill)
            else
              close_and_maybe_flip(position, side, quantity, price, risk_unit, contract_value, fill, flip_leverage: fill_leverage)
            end
          @wallet.recompute_from_ledger!
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

    def pnl_side_for_position(side)
      side == "buy" ? :buy : :sell
    end

    def resolve_leverage(explicit)
      v = explicit.to_i
      return v if v.positive?

      p = @product.default_leverage.to_i
      p.positive? ? p : 1
    end

    def initial_margin(price, quantity, contract_value, leverage)
      self.class.estimate_margin_usd(
        quantity: quantity,
        price: price,
        contract_value: contract_value,
        leverage: leverage
      )
    end

    def to_inr(usd_amount)
      (usd_amount.to_d * @usd_inr_rate).round(2)
    end

    def record_entry_fee!(fill, quantity:, price:)
      rate = Fees.taker_fee_rate_for_product(@product)
      notional = Fees.notional_usd(quantity: quantity, price: price, contract_value: @product.contract_value)
      fee_usd = Fees.fee_usd(notional_usd: notional, fee_rate: rate)
      finr = Fees.fee_inr(fee_usd: fee_usd, usd_inr_rate: @usd_inr_rate)
      return if finr.zero?

      write_ledger!(
        "commission",
        :debit,
        finr,
        fill,
        meta: { "leg" => "entry" }
      )
    end

    def record_exit_fee!(fill, quantity:, price:)
      rate = Fees.taker_fee_rate_for_product(@product)
      notional = Fees.notional_usd(quantity: quantity, price: price, contract_value: @product.contract_value)
      fee_usd = Fees.fee_usd(notional_usd: notional, fee_rate: rate)
      finr = Fees.fee_inr(fee_usd: fee_usd, usd_inr_rate: @usd_inr_rate)
      return if finr.zero?

      write_ledger!(
        "commission",
        :debit,
        finr,
        fill,
        meta: { "leg" => "exit" }
      )
    end

    def open_position(side, quantity, price, risk_unit, contract_value, fill, leverage:)
      lev = resolve_leverage(leverage)
      margin_usd = initial_margin(price, quantity, contract_value, lev)
      margin_inr = to_inr(margin_usd)
      ensure_sufficient_margin!(required_margin_inr: margin_inr)

      write_ledger!("margin_reserved", :debit, margin_inr, fill)
      record_entry_fee!(fill, quantity: quantity, price: price)

      PaperPosition.create!(
        paper_wallet: @wallet,
        paper_product_snapshot: @product,
        side: side,
        net_quantity: quantity,
        avg_entry_price: price,
        risk_unit_per_contract: risk_unit,
        leverage: lev
      )

      Result.new(action: :opened, realized_pnl: 0.to_d, margin_delta: margin_usd)
    end

    def add_position(position, quantity, price, contract_value, fill)
      lev = position.leverage.to_i
      lev = 1 unless lev.positive?
      margin_usd = initial_margin(price, quantity, contract_value, lev)
      margin_inr = to_inr(margin_usd)
      ensure_sufficient_margin!(required_margin_inr: margin_inr)

      prev_qty = position.net_quantity.to_d
      new_qty = prev_qty + quantity
      new_avg = ((prev_qty * position.avg_entry_price.to_d) + (quantity * price)) / new_qty

      write_ledger!("margin_reserved", :debit, margin_inr, fill)
      record_entry_fee!(fill, quantity: quantity, price: price)
      position.update!(net_quantity: new_qty.to_i, avg_entry_price: new_avg)

      Result.new(action: :added, realized_pnl: 0.to_d, margin_delta: margin_usd)
    end

    def close_and_maybe_flip(position, incoming_side, quantity, price, risk_unit, contract_value, fill, flip_leverage:)
      pos_qty = position.net_quantity
      close_qty = [ pos_qty, quantity ].min
      excess = quantity - close_qty

      exit_rate = Fees.taker_fee_rate_for_product(@product)
      exit_notional = Fees.notional_usd(quantity: close_qty, price: price, contract_value: @product.contract_value)
      exit_fee_usd = Fees.fee_usd(notional_usd: exit_notional, fee_rate: exit_rate)

      gross_row = PnlCalculator.call(
        side: pnl_side_for_position(position.side),
        entry_price: position.avg_entry_price,
        exit_price: price,
        quantity: close_qty,
        risk_unit_value: risk_unit,
        fees: 0.to_d
      )
      gross_pnl_usd = gross_row[:gross_pnl]
      net_row = PnlCalculator.call(
        side: pnl_side_for_position(position.side),
        entry_price: position.avg_entry_price,
        exit_price: price,
        quantity: close_qty,
        risk_unit_value: risk_unit,
        fees: exit_fee_usd
      )

      released_inr = proportional_released_margin_inr(
        current_quantity: pos_qty,
        close_quantity: close_qty,
        fallback_entry_price: position.avg_entry_price,
        fallback_leverage: position.leverage,
        fallback_contract_value: contract_value
      )
      released_usd = @usd_inr_rate.positive? ? (released_inr / @usd_inr_rate) : 0.to_d
      new_qty = pos_qty - close_qty

      ActiveRecord::Base.transaction do
        record_exit_fee!(fill, quantity: close_qty, price: price)
        write_ledger!("margin_released", :credit, released_inr, fill)

        if gross_pnl_usd >= 0
          write_ledger!("realized_pnl", :credit, to_inr(gross_pnl_usd), fill)
        else
          write_ledger!("realized_pnl", :debit, to_inr(gross_pnl_usd.abs), fill)
        end

        if new_qty.zero?
          position.destroy!
        else
          position.update!(net_quantity: new_qty)
        end
      end

      new_reserve_usd = 0.to_d
      action = :closed
      if excess.positive?
        flip_lev = resolve_leverage(flip_leverage)
        begin
          ActiveRecord::Base.transaction(requires_new: true) do
            new_reserve_usd = open_after_flip(
              incoming_side,
              excess,
              price,
              risk_unit,
              contract_value,
              fill,
              leverage: flip_lev
            )
          end
          action = :flipped
        rescue InsufficientMarginError, ActiveRecord::RecordInvalid => e
          Rails.logger.warn("[PaperTrading::PositionManager] flip skipped after close: #{e.message}")
        end
      end

      Result.new(action: action, realized_pnl: net_row[:net_pnl], margin_delta: new_reserve_usd - released_usd)
    end

    def open_after_flip(side, quantity, price, risk_unit, contract_value, fill, leverage:)
      lev = resolve_leverage(leverage)
      margin_usd = initial_margin(price, quantity, contract_value, lev)
      margin_inr = to_inr(margin_usd)
      ensure_sufficient_margin!(required_margin_inr: margin_inr)

      write_ledger!("margin_reserved", :debit, margin_inr, fill)
      record_entry_fee!(fill, quantity: quantity, price: price)
      PaperPosition.create!(
        paper_wallet: @wallet,
        paper_product_snapshot: @product,
        side: side,
        net_quantity: quantity,
        avg_entry_price: price,
        risk_unit_per_contract: risk_unit,
        leverage: lev
      )
      margin_usd
    end

    def ensure_sufficient_margin!(required_margin_inr:)
      available_inr = @wallet.available_inr.to_d
      required = required_margin_inr.to_d.round(2)
      return if available_inr >= required

      raise InsufficientMarginError,
            "insufficient paper margin: required_inr=#{required.to_s("F")} available_inr=#{available_inr.to_s("F")}"
    end

    def proportional_released_margin_inr(current_quantity:, close_quantity:, fallback_entry_price:, fallback_leverage:, fallback_contract_value:)
      current = current_quantity.to_d
      close = close_quantity.to_d
      return 0.to_d if current <= 0 || close <= 0

      product_reserved = current_reserved_margin_inr_for_product
      if product_reserved <= 0
        lev = resolve_leverage(fallback_leverage)
        fallback = initial_margin(fallback_entry_price, close, fallback_contract_value, lev)
        Rails.logger.warn(
          "[PaperTrading::PositionManager] ledger reserved margin missing for wallet=#{@wallet.id} product=#{@product.id}; using fallback release"
        )
        return to_inr(fallback)
      end

      ((product_reserved * close) / current).round(2)
    end

    def current_reserved_margin_inr_for_product
      rows = PaperWalletLedgerEntry.where(
        paper_wallet_id: @wallet.id,
        entry_type: %w[margin_reserved margin_released],
        reference_type: "PaperFill"
      ).joins("INNER JOIN paper_fills ON paper_fills.id = paper_wallet_ledger_entries.reference_id")
       .joins("INNER JOIN paper_orders ON paper_orders.id = paper_fills.paper_order_id")
       .where("paper_orders.paper_product_snapshot_id = ?", @product.id)

      rows.reduce(0.to_d) do |sum, row|
        amount = row.amount_inr.to_d
        case [ row.entry_type, row.direction ]
        when [ "margin_reserved", "debit" ] then sum + amount
        when [ "margin_reserved", "credit" ] then sum - amount
        when [ "margin_released", "credit" ] then sum - amount
        when [ "margin_released", "debit" ] then sum + amount
        else sum
        end
      end
    end

    def write_ledger!(entry_type, direction, amount_inr, reference, meta: {})
      PaperWalletLedgerEntry.create!(
        paper_wallet: @wallet,
        entry_type: entry_type.to_s,
        direction: direction.to_s,
        amount_inr: amount_inr.round(2),
        reference: reference,
        meta: meta.stringify_keys
      )
    end
  end
end
