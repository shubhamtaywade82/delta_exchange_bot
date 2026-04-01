# frozen_string_literal: true

module Trading
  module Ledger
    # Average-cost, signed-quantity position state from chronological fills (linear perps).
    class NetPositionCalculator
      Result = Struct.new(
        :signed_qty,
        :avg_entry,
        :cumulative_realized_pnl,
        keyword_init: true
      )

      class << self
        # @param fills [Array<Fill>] orders must be loaded for #signed_quantity
        def from_fills(fills)
          q = 0.to_d
          avg = 0.to_d
          realized = 0.to_d

          sorted_fills(fills).each do |fill|
            dq = fill.signed_quantity
            price = fill.price&.to_d
            next if dq.zero? || price.nil? || price.zero?

            if q.zero?
              q = dq
              avg = price
              next
            end

            if same_direction?(q, dq)
              q, avg = add_same_side(q, avg, dq, price)
              next
            end

            r, q, avg = reduce_or_flip(q, avg, dq, price)
            realized += r
          end

          Result.new(
            signed_qty: q,
            avg_entry: q.zero? ? nil : avg,
            cumulative_realized_pnl: realized
          )
        end

        def realized_delta_for_append(prior_fills, new_fill)
          before = from_fills(prior_fills).cumulative_realized_pnl
          after = from_fills(prior_fills + [new_fill]).cumulative_realized_pnl
          after - before
        end

        private

        def sorted_fills(fills)
          fills.sort_by { |f| [f.filled_at, f.id.to_i] }
        end

        def same_direction?(q, dq)
          (q.positive? && dq.positive?) || (q.negative? && dq.negative?)
        end

        def add_same_side(q, avg, dq, price)
          new_q = q + dq
          new_avg = (q.abs * avg + dq.abs * price) / new_q.abs
          [new_q, new_avg]
        end

        # @return [Array<RealizedPnL, new_q, new_avg>]
        def reduce_or_flip(q, avg, dq, price)
          realized = 0.to_d

          if q.positive? && dq.negative?
            close_amt = [q, dq.abs].min
            realized = (price - avg) * close_amt
            new_q = q + dq
            new_avg = if new_q.zero?
                        0.to_d
                      elsif new_q.positive?
                        avg
                      else
                        price
                      end
            return [realized, new_q, new_avg]
          end

          if q.negative? && dq.positive?
            close_amt = [q.abs, dq].min
            realized = (avg - price) * close_amt
            new_q = q + dq
            new_avg = if new_q.zero?
                        0.to_d
                      elsif new_q.negative?
                        avg
                      else
                        price
                      end
            return [realized, new_q, new_avg]
          end

          [realized, q, avg]
        end
      end
    end
  end
end
