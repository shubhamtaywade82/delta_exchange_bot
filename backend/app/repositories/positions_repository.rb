# frozen_string_literal: true

module PositionsRepository
  # @param portfolio_id [Integer, nil] when nil, first active row for +symbol+ (legacy / tick handlers without portfolio context).
  def self.open_for(symbol, portfolio_id: nil)
    scope = if portfolio_id.nil?
              Position.active.where(symbol: symbol)
            else
              Position.active_for_portfolio(portfolio_id).where(symbol: symbol)
            end

    scope.first
  end

  def self.normalize_net_side(side)
    s = side.to_s
    return "long" if %w[buy long].include?(s)
    return "short" if %w[sell short].include?(s)

    s
  end

  # A fill closes exposure when it is opposite to the open position (buy closes short, sell closes long).
  def self.closing_fill?(order)
    existing = open_for(order.symbol, portfolio_id: order.portfolio_id)
    return false unless existing

    opposite_fill?(existing, order)
  end

  def self.opposite_fill?(position, order)
    case normalize_net_side(position.side)
    when "long"  then order.side.to_s == "sell"
    when "short" then order.side.to_s == "buy"
    else false
    end
  end
  private_class_method :opposite_fill?

  def self.snapshot_for_closing_trade(order)
    existing = open_for(order.symbol, portfolio_id: order.portfolio_id)
    return nil unless existing

    opposite_fill?(existing, order) ? existing : nil
  end

  # @param closing [Boolean, nil] pass pre-computed close decision to avoid re-querying.
  def self.apply_fill_from_order!(order, closing: nil)
    is_closing = closing.nil? ? closing_fill?(order) : closing

    if is_closing
      close!(order.symbol, order.portfolio_id)
    else
      upsert_from_order(order)
    end
  end

  def self.upsert_from_order(order)
    position = Position.active_for_portfolio(order.portfolio_id).find_or_initialize_by(symbol: order.symbol)
    position.portfolio_id = order.portfolio_id
    position.assign_attributes(
      side:        order.side.to_s == "buy" ? "long" : "short",
      size:        order.filled_qty,
      entry_price: order.avg_fill_price,
      status:      "filled"
    )
    position.entry_time ||= Time.current
    position.save!
    position
  end

  def self.close!(symbol, portfolio_id)
    Position.active_for_portfolio(portfolio_id).where(symbol: symbol).update_all(
      status: "closed", exit_time: Time.current
    )
  end
end
