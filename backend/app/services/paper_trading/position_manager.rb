# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module PaperTrading
  class PositionManager
    Result = Struct.new(:action, :realized_pnl, :margin_delta, keyword_init: true)

    def initialize(wallet:, product:, usd_inr_rate: nil)
      @wallet = wallet
      @product = product
      @usd_inr_rate = (usd_inr_rate || Finance::UsdInrRate.current).to_d
    end

    # Caller must wrap in a transaction. Idempotent per PaperFill (movement rows only).
    def apply_fill(fill:, fill_side:, quantity:, price:, leverage: nil)
      return Result.new(action: :noop, realized_pnl: 0.to_d, margin_delta: 0.to_d) if fill_movement_applied?(fill)

      side = normalize_side(fill_side)
      quantity = Integer(quantity)
      price = price.to_d
      unit = @product.risk_unit_per_contract.to_d
      fill_leverage = resolve_leverage(leverage)

      position = PaperPosition.lock.find_by(
        paper_wallet_id: @wallet.id,
        paper_product_snapshot_id: @product.id
      )

      result =
        if position.nil? || position.net_quantity.zero?
          open_position(side, quantity, price, unit, fill, leverage: fill_leverage)
        elsif position.side == side
          add_position(position, quantity, price, unit, fill)
        else
          close_and_maybe_flip(position, side, quantity, price, unit, fill, flip_leverage: fill_leverage)
        end

      @wallet.reload
      @wallet.recompute_from_ledger!
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

    def initial_margin(price, quantity, unit, leverage)
      lev = [ leverage.to_i, 1 ].max.to_d
      (price.to_d * quantity * unit) / lev
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

    def open_position(side, quantity, price, unit, fill, leverage:)
      lev = resolve_leverage(leverage)
      PaperPosition.create!(
        paper_wallet: @wallet,
        paper_product_snapshot: @product,
        side: side,
        net_quantity: quantity,
        avg_entry_price: price,
        risk_unit_per_contract: unit,
        leverage: lev
      )

      margin_usd = initial_margin(price, quantity, unit, lev)
      margin_inr = to_inr(margin_usd)
      write_ledger!("margin_reserved", :debit, margin_inr, fill)
      record_entry_fee!(fill, quantity: quantity, price: price)

      Result.new(action: :opened, realized_pnl: 0.to_d, margin_delta: margin_usd)
    end

    def add_position(position, quantity, price, unit, fill)
      prev_qty = position.net_quantity.to_d
      new_qty = prev_qty + quantity
      new_avg = ((prev_qty * position.avg_entry_price.to_d) + (quantity * price)) / new_qty
      position.update!(net_quantity: new_qty.to_i, avg_entry_price: new_avg)

      lev = position.leverage.to_i
      lev = 1 unless lev.positive?
      margin_usd = initial_margin(price, quantity, unit, lev)
      margin_inr = to_inr(margin_usd)
      write_ledger!("margin_reserved", :debit, margin_inr, fill)
      record_entry_fee!(fill, quantity: quantity, price: price)

      Result.new(action: :added, realized_pnl: 0.to_d, margin_delta: margin_usd)
    end

    def close_and_maybe_flip(position, incoming_side, quantity, price, unit, fill, flip_leverage:)
      pos_qty = position.net_quantity
      close_qty = [ pos_qty, quantity ].min
      excess = quantity - close_qty

      exit_rate = Fees.taker_fee_rate_for_product(@product)
      exit_notional = Fees.notional_usd(quantity: close_qty, price: price, contract_value: @product.contract_value)
      exit_fee_usd = Fees.fee_usd(notional_usd: exit_notional, fee_rate: exit_rate)

      record_exit_fee!(fill, quantity: close_qty, price: price)

      gross_row = PnlCalculator.call(
        side: pnl_side_for_position(position.side),
        entry_price: position.avg_entry_price,
        exit_price: price,
        quantity: close_qty,
        risk_unit_value: unit,
        fees: 0.to_d
      )
      gross_pnl_usd = gross_row[:gross_pnl]
      net_row = PnlCalculator.call(
        side: pnl_side_for_position(position.side),
        entry_price: position.avg_entry_price,
        exit_price: price,
        quantity: close_qty,
        risk_unit_value: unit,
        fees: exit_fee_usd
      )

      lev = position.leverage.to_i
      lev = 1 unless lev.positive?
      released_usd = initial_margin(position.avg_entry_price, close_qty, unit, lev)
      released_inr = to_inr(released_usd)
      write_ledger!("margin_released", :credit, released_inr, fill)

      if gross_pnl_usd >= 0
        write_ledger!("realized_pnl", :credit, to_inr(gross_pnl_usd), fill)
      else
        write_ledger!("realized_pnl", :debit, to_inr(gross_pnl_usd.abs), fill)
      end

      new_reserve_usd = 0.to_d
      new_qty = pos_qty - close_qty
      if new_qty.zero?
        position.destroy!
      else
        position.update!(net_quantity: new_qty)
      end

      action = :closed
      if excess.positive?
        flip_lev = resolve_leverage(flip_leverage)
        new_reserve_usd = open_after_flip(incoming_side, excess, price, unit, fill, leverage: flip_lev)
        action = :flipped
      end

      Result.new(action: action, realized_pnl: net_row[:net_pnl], margin_delta: new_reserve_usd - released_usd)
    end

    def open_after_flip(side, quantity, price, unit, fill, leverage:)
      lev = resolve_leverage(leverage)
      PaperPosition.create!(
        paper_wallet: @wallet,
        paper_product_snapshot: @product,
        side: side,
        net_quantity: quantity,
        avg_entry_price: price,
        risk_unit_per_contract: unit,
        leverage: lev
      )
      margin_usd = initial_margin(price, quantity, unit, lev)
      margin_inr = to_inr(margin_usd)
      write_ledger!("margin_reserved", :debit, margin_inr, fill)
      record_entry_fee!(fill, quantity: quantity, price: price)
      margin_usd
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
