# frozen_string_literal: true

module Trading
  module Dashboard
    # Price-space summary of how close mark/LTP is to runner-driven exit triggers.
    # Matches +Handlers::TrailingStopHandler+ (stop hit) and +NearLiquidationExit+ (distance formula).
    class PositionExitSummary
      def self.call(position:, mark_price:)
        new(position: position, mark_price: mark_price).to_h
      end

      def initialize(position:, mark_price:)
        @position = position
        @mark = mark_price&.to_d
      end

      def to_h
        return {} if @mark.nil? || !@mark.positive?

        trailing = trailing_stop_hash
        liq = liquidation_hash
        nearest = nearest_exit(trailing, liq)

        out = {}
        out[:trailing_stop] = trailing if trailing
        out[:liquidation] = liq if liq
        out[:nearest_exit] = nearest if nearest
        out
      end

      private

      def long_side?
        s = @position.side.to_s.downcase
        %w[long buy].include?(s)
      end

      def trailing_stop_hash
        stop = @position.stop_price&.to_d
        return nil unless stop&.positive?

        if long_side?
          room = @mark - stop
          room_pct = pct(room / @mark)
          at_risk = room <= 0
        else
          room = stop - @mark
          room_pct = pct(room / @mark)
          at_risk = room <= 0
        end

        {
          trigger_price: stop.round(8).to_f,
          room_pct: room_pct,
          at_risk: at_risk
        }
      end

      def liquidation_hash
        liq = @position.liquidation_price&.to_d
        return nil unless liq&.positive?

        frac = liquidation_distance_fraction
        return nil if frac.nil? || frac.negative?

        dist_pct = pct(frac)
        {
          trigger_price: liq.round(8).to_f,
          distance_pct: dist_pct,
          within_near_liquidation_band: frac < NearLiquidationExit::BUFFER_PCT
        }
      end

      def liquidation_distance_fraction
        liq = @position.liquidation_price.to_d
        if long_side?
          (@mark - liq) / @mark
        else
          (liq - @mark) / @mark
        end
      end

      def nearest_exit(trailing, liq)
        if trailing&.fetch(:at_risk)
          return {
            kind: "trailing_stop",
            room_pct: 0.0,
            trigger_price: trailing[:trigger_price],
            note: "at_or_past_stop"
          }
        end

        candidates = []
        if trailing
          candidates << {
            kind: "trailing_stop",
            room_pct: trailing[:room_pct].to_f,
            trigger_price: trailing[:trigger_price]
          }
        end
        if liq
          candidates << {
            kind: "liquidation",
            room_pct: liq[:distance_pct].to_f,
            trigger_price: liq[:trigger_price]
          }
        end

        return nil if candidates.empty?

        candidates.min_by { |c| c[:room_pct] }
      end

      def pct(ratio)
        (ratio.to_d * 100).round(3).to_f
      end
    end
  end
end
