# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module PaperTrading
  class PositionManager
    Result = Struct.new(:action, :realized_pnl, :margin_delta, keyword_init: true)

    def initialize(wallet:, product:)
      @wallet = wallet
      @product = product
    end

    # Caller must wrap in a transaction. Idempotent per PaperFill via ledger reference uniqueness.
    def apply_fill(fill:, fill_side:, quantity:, price:)
      if PaperWalletLedgerEntry.exists?(paper_wallet: @wallet, reference: fill)
        return Result.new(action: :noop, realized_pnl: 0.to_d, margin_delta: 0.to_d)
      end

      side = normalize_side(fill_side)
      quantity = Integer(quantity)
      price = price.to_d
      unit = @product.risk_unit_per_contract.to_d

      position = PaperPosition.lock.find_by(
        paper_wallet_id: @wallet.id,
        paper_product_snapshot_id: @product.id
      )

      if position.nil? || position.net_quantity.zero?
        open_position(side, quantity, price, unit, fill)
      elsif position.side == side
        add_position(position, quantity, price, unit, fill)
      else
        close_and_maybe_flip(position, side, quantity, price, unit, fill)
      end
    end

    private

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

    def open_position(side, quantity, price, unit, fill)
      position = PaperPosition.create!(
        paper_wallet: @wallet,
        paper_product_snapshot: @product,
        side: side,
        net_quantity: quantity,
        avg_entry_price: price,
        risk_unit_per_contract: unit
      )

      notional = price * quantity * unit
      write_ledger!(:margin_reserved, :debit, notional, fill)
      bump_reserved_margin!(notional)

      Result.new(action: :opened, realized_pnl: 0.to_d, margin_delta: notional)
    end

    def add_position(position, quantity, price, unit, fill)
      prev_qty = position.net_quantity.to_d
      new_qty = prev_qty + quantity
      new_avg = ((prev_qty * position.avg_entry_price.to_d) + (quantity * price)) / new_qty
      position.update!(net_quantity: new_qty.to_i, avg_entry_price: new_avg)

      notional = price * quantity * unit
      write_ledger!(:margin_reserved, :debit, notional, fill)
      bump_reserved_margin!(notional)

      Result.new(action: :added, realized_pnl: 0.to_d, margin_delta: notional)
    end

    def close_and_maybe_flip(position, incoming_side, quantity, price, unit, fill)
      pos_qty = position.net_quantity
      close_qty = [ pos_qty, quantity ].min
      excess = quantity - close_qty

      pnl_hash = PnlCalculator.call(
        side: pnl_side_for_position(position.side),
        entry_price: position.avg_entry_price,
        exit_price: price,
        quantity: close_qty,
        risk_unit_value: unit
      )
      net_pnl = pnl_hash[:net_pnl]

      released = position.avg_entry_price.to_d * close_qty * unit
      write_ledger!(:margin_released, :credit, released, fill)
      write_ledger!(:realized_pnl, net_pnl >= 0 ? :credit : :debit, net_pnl.abs, fill)

      new_reserve = 0.to_d
      new_qty = pos_qty - close_qty
      if new_qty.zero?
        position.destroy!
      else
        position.update!(net_quantity: new_qty)
      end

      action = :closed
      if excess.positive?
        open_after_flip(incoming_side, excess, price, unit, fill)
        new_reserve = price * excess * unit
        action = :flipped
      end

      @wallet.with_lock do
        @wallet.update!(
          realized_pnl: @wallet.realized_pnl.to_d + net_pnl,
          reserved_margin: [ @wallet.reserved_margin.to_d - released + new_reserve, 0.to_d ].max
        )
      end

      Result.new(action: action, realized_pnl: net_pnl, margin_delta: new_reserve - released)
    end

    def open_after_flip(side, quantity, price, unit, fill)
      PaperPosition.create!(
        paper_wallet: @wallet,
        paper_product_snapshot: @product,
        side: side,
        net_quantity: quantity,
        avg_entry_price: price,
        risk_unit_per_contract: unit
      )
      notional = price * quantity * unit
      write_ledger!(:margin_reserved, :debit, notional, fill)
    end

    def write_ledger!(entry_type, direction, amount, reference)
      PaperWalletLedgerEntry.create!(
        paper_wallet: @wallet,
        entry_type: entry_type.to_s,
        direction: direction.to_s,
        amount: amount.abs,
        reference: reference
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def bump_reserved_margin!(delta)
      @wallet.with_lock do
        @wallet.update!(reserved_margin: @wallet.reserved_margin.to_d + delta)
      end
    end
  end
end
