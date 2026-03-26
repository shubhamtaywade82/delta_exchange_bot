# frozen_string_literal: true

module Bot
  module Execution
    class PositionTracker
      def initialize
        @positions = {}
        @mutex     = Mutex.new
      end

      def open(attrs)
        @mutex.synchronize do
          symbol         = attrs.fetch(:symbol)
          trail_pct      = attrs.fetch(:trail_pct).to_f / 100.0
          entry          = attrs.fetch(:entry_price).to_f
          side           = attrs.fetch(:side)
          stop           = side == :long ? entry * (1.0 - trail_pct) : entry * (1.0 + trail_pct)

          @positions[symbol] = {
            symbol:         symbol,
            side:           side,
            entry:          entry,
            lots:           attrs.fetch(:lots),
            leverage:       attrs.fetch(:leverage).to_f,
            contract_value: attrs.fetch(:contract_value).to_f,
            trail_pct:      attrs.fetch(:trail_pct).to_f,
            peak_price:     entry,
            stop_price:     stop,
            entry_time:     Time.now.utc
          }
        end
      end

      # Returns :exit if stop was hit, nil otherwise
      def update_trailing_stop(symbol, ltp)
        @mutex.synchronize do
          pos = @positions[symbol]
          return nil unless pos

          trail_pct = pos[:trail_pct] / 100.0

          if pos[:side] == :long
            if ltp > pos[:peak_price]
              pos[:peak_price] = ltp
              pos[:stop_price] = ltp * (1.0 - trail_pct)
            end
            return :exit if ltp <= pos[:stop_price]
          else
            if ltp < pos[:peak_price]
              pos[:peak_price] = ltp
              pos[:stop_price] = ltp * (1.0 + trail_pct)
            end
            return :exit if ltp >= pos[:stop_price]
          end

          nil
        end
      end

      def close(symbol)
        @mutex.synchronize { @positions.delete(symbol) }
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

      # Returns a full portfolio snapshot given a prices hash { symbol => ltp }
      def snapshot(prices)
        @mutex.synchronize do
          positions = @positions.transform_values do |pos|
            ltp    = prices[pos[:symbol]]
            margin = margin_for(pos)
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

      private

      def margin_for(pos)
        return 0.0 if pos[:leverage].zero? || pos[:contract_value].zero?
        (pos[:lots] * pos[:contract_value] * pos[:entry]) / pos[:leverage]
      end

      def unrealized_pnl_for(pos, ltp)
        multiplier = pos[:side] == :long ? 1 : -1
        multiplier * (ltp - pos[:entry]) * pos[:lots] * pos[:contract_value]
      end
    end
  end
end
