# frozen_string_literal: true

module PaperTrading
  # Pure aggregation from fills; derives side, contracts, avg entry, and used margin.
  class PositionAggregator
    Snapshot = Struct.new(
      :symbol,
      :side,
      :contracts,
      :avg_entry_price,
      :contract_value,
      :used_margin_inr,
      keyword_init: true
    )

    # @param fills [Enumerable<PaperFill>] product-scoped fills ordered by fill time
    # @return [Snapshot, nil] nil when net position is flat
    def self.call(fills)
      ordered_fills = Array(fills).sort_by { |fill| [ fill.filled_at, fill.id || 0 ] }
      return if ordered_fills.empty?

      product = ordered_fills.first.paper_order.paper_product_snapshot
      inventory = []

      ordered_fills.each do |fill|
        side = normalize_side(fill.paper_order.side)
        apply_fill(inventory, fill, side)
      end

      return if inventory.empty?

      side = inventory.first[:side]
      contracts = inventory.sum { |row| row[:qty] }
      weighted_sum = inventory.sum { |row| row[:qty] * row[:entry_price] }
      avg_entry = weighted_sum / contracts.to_d
      used_margin_inr = inventory.sum { |row| row[:margin_inr] }

      Snapshot.new(
        symbol: product.symbol,
        side: side,
        contracts: contracts,
        avg_entry_price: avg_entry,
        contract_value: product.contract_value.to_d,
        used_margin_inr: used_margin_inr.round(2)
      )
    end

    class << self
      private

      def apply_fill(inventory, fill, side)
        qty = fill.filled_qty.to_i
        closed = fill.closed_qty.to_i
        open_qty = qty - closed
        return unless open_qty.positive?

        consumed = consume_opposite!(inventory, side: side, quantity: open_qty)
        return if open_qty <= consumed

        remaining = open_qty - consumed
        inventory << {
          side: side,
          qty: remaining,
          entry_price: fill.price.to_d,
          margin_inr: proportional_margin(fill, remaining: remaining)
        }
      end

      def consume_opposite!(inventory, side:, quantity:)
        opposite = side == "buy" ? "sell" : "buy"
        remaining = quantity

        inventory.each do |row|
          break unless remaining.positive?
          next unless row[:side] == opposite

          consumed = [ row[:qty], remaining ].min
          ratio = consumed.to_d / row[:qty].to_d
          row[:margin_inr] = (row[:margin_inr] * (1 - ratio)).round(2)
          row[:qty] -= consumed
          remaining -= consumed
        end

        inventory.reject! { |row| row[:qty].zero? }
        quantity - remaining
      end

      def proportional_margin(fill, remaining:)
        return 0.to_d if fill.filled_qty.to_i <= 0

        fill.margin_inr_per_fill.to_d * remaining.to_d / fill.filled_qty.to_d
      end

      def normalize_side(raw)
        case raw.to_s.downcase
        when "long", "buy" then "buy"
        when "short", "sell" then "sell"
        else
          raise ArgumentError, "invalid side: #{raw}"
        end
      end
    end
  end
end
