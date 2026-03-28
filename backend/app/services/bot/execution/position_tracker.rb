# frozen_string_literal: true

module Bot
  module Execution
    class PositionTracker
      def initialize
        @mutex = Mutex.new
        refresh_from_db
      end

      def refresh_from_db
        @mutex.synchronize do
          @positions = {}
          Position.where(status: "open").find_each do |pos|
            @positions[pos.symbol] = pos_to_hash(pos)
          end
        end
      end

      def open(attrs)
        @mutex.synchronize do
          symbol    = attrs.fetch(:symbol)
          trail_pct = attrs.fetch(:trail_pct).to_f / 100.0
          entry     = attrs.fetch(:entry_price).to_f
          side      = attrs.fetch(:side)
          stop      = side == :long ? entry * (1.0 - trail_pct) : entry * (1.0 + trail_pct)

          return nil if Position.exists?(symbol: symbol, status: "open")

          pos = Position.create!(
            symbol:         symbol,
            side:           side.to_s,
            status:         "open",
            entry_price:    entry,
            size:           attrs.fetch(:lots),
            leverage:       attrs.fetch(:leverage).to_i,
            margin:         margin_for(attrs),
            entry_time:     Time.now.utc,
            peak_price:     entry,
            stop_price:     stop,
            trail_pct:      attrs.fetch(:trail_pct).to_f,
            product_id:     attrs.fetch(:product_id, nil),
            contract_value: attrs.fetch(:contract_value).to_f
          )

          @positions[symbol] = pos_to_hash(pos)
        end
      end

      def update_trailing_stop(symbol, ltp)
        @mutex.synchronize do
          pos_hash = @positions[symbol]
          return nil unless pos_hash

          trail_pct = pos_hash[:trail_pct] / 100.0
          updated = false

          if pos_hash[:side] == :long
            if ltp > pos_hash[:peak_price]
              pos_hash[:peak_price] = ltp
              pos_hash[:stop_price] = ltp * (1.0 - trail_pct)
              updated = true
            end
            return :exit if ltp <= pos_hash[:stop_price]
          else
            if ltp < pos_hash[:peak_price]
              pos_hash[:peak_price] = ltp
              pos_hash[:stop_price] = ltp * (1.0 + trail_pct)
              updated = true
            end
            return :exit if ltp >= pos_hash[:stop_price]
          end

          if updated
            Position.where(symbol: symbol, status: "open").update_all(
              peak_price: pos_hash[:peak_price],
              stop_price: pos_hash[:stop_price]
            )
          end

          nil
        end
      end

      def close(symbol, exit_price: nil, pnl_usd: nil, pnl_inr: nil)
        @mutex.synchronize do
          Position.where(symbol: symbol, status: "open").update_all(
            status: "closed",
            exit_price: exit_price,
            exit_time: Time.now.utc,
            pnl_usd: pnl_usd,
            pnl_inr: pnl_inr
          )
          @positions.delete(symbol)
        end
      end

      def get(symbol)
        @mutex.synchronize { @positions[symbol]&.dup }
      end

      def open?(symbol)
        @mutex.synchronize { @positions.key?(symbol) }
      end

      def count
        @mutex.synchronize { @positions.size }
      end

      def all
        @mutex.synchronize { @positions.transform_values(&:dup) }
      end

      def snapshot(prices)
        @mutex.synchronize do
          positions = @positions.transform_values do |pos|
            ltp    = prices[pos[:symbol]]
            margin = pos[:margin_usd]
            upnl   = ltp ? unrealized_pnl_for(pos, ltp) : nil
            duration_s = (Time.now.utc - pos[:entry_time]).to_i

            {
              symbol:         pos[:symbol],
              side:           pos[:side],
              entry_price:    pos[:entry].round(4),
              ltp:            ltp&.round(4),
              lots:           pos[:lots],
              leverage:       pos[:leverage].to_i,
              peak_price:     pos[:peak_price].round(4),
              stop_price:     pos[:stop_price].round(4),
              margin_usd:     margin.round(2),
              unrealized_pnl: upnl&.round(2),
              duration_s:     duration_s
            }
          end

          total_blocked    = positions.values.sum { |p| p[:margin_usd] }
          total_unrealized = positions.values.filter_map { |p| p[:unrealized_pnl] }.sum

          {
            positions:        positions,
            blocked_margin:   total_blocked.round(2),
            unrealized_pnl:   total_unrealized.round(2),
            open_count:       positions.size
          }
        end
      end

      def persist_state(prices)
        @mutex.synchronize do
          data = snapshot(prices)
          Redis.new.set("delta:positions:live", data.to_json)
        rescue StandardError => e
          puts "Error persisting positions to Redis: #{e.message}"
        end
      end

      private

      def pos_to_hash(pos)
        {
          symbol:         pos.symbol,
          side:           pos.side.to_sym,
          entry:          pos.entry_price.to_f,
          lots:           pos.size.to_i,
          leverage:       pos.leverage.to_f,
          contract_value: pos.contract_value.to_f,
          trail_pct:      pos.trail_pct.to_f,
          peak_price:     pos.peak_price.to_f,
          stop_price:     pos.stop_price.to_f,
          entry_time:     pos.entry_time,
          margin_usd:     pos.margin.to_f
        }
      end

      def margin_for(attrs)
        leverage       = attrs.fetch(:leverage).to_f
        contract_value = attrs.fetch(:contract_value).to_f
        entry          = attrs.fetch(:entry_price).to_f
        lots           = attrs.fetch(:lots).to_f
        return 0.0 if leverage.zero? || contract_value.zero?
        (lots * contract_value * entry) / leverage
      end

      def unrealized_pnl_for(pos, ltp)
        # We need contract_value here. If it's not in the hash, we might need to store it in DB
        # or pass it from ProductCache. For now, I'll assume it's in the hash if we opened it.
        # But for re-adopted positions, we need to ensure it's there.
        cv = pos[:contract_value] || 0.0 
        multiplier = pos[:side] == :long ? 1 : -1
        multiplier * (ltp - pos[:entry]) * pos[:lots] * cv
      end
    end
  end
end
