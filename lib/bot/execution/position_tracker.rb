# frozen_string_literal: true

module Bot
  module Execution
    class PositionTracker
      def initialize
        @positions = {}
        @mutex     = Mutex.new
      end

      def open(attrs)
        symbol    = attrs[:symbol]
        trail_pct = attrs[:trail_pct] / 100.0
        entry     = attrs[:entry_price].to_f
        side      = attrs[:side]

        stop = if side == :long
                 entry * (1.0 - trail_pct)
               else
                 entry * (1.0 + trail_pct)
               end

        @mutex.synchronize do
          @positions[symbol] = attrs.merge(peak_price: entry, stop_price: stop)
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
    end
  end
end
