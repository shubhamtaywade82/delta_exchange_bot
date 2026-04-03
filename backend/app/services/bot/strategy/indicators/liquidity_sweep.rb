# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      # Detects recent wick beyond a swing pivot with close back inside (classic liquidity grab).
      module LiquiditySweep
        def self.recent(candles, swing: 3, lookback: 25)
          return nil if candles.size < swing * 2 + 3

          start = [candles.size - lookback, swing].max
          highs = SwingFractal.pivot_high_indices(candles, left: swing, right: swing).select { |i| i >= start }
          lows = SwingFractal.pivot_low_indices(candles, left: swing, right: swing).select { |i| i >= start }
          last = candles.last
          hi = last[:high].to_f
          lo = last[:low].to_f
          close = last[:close].to_f

          highs.each do |idx|
            level = candles[idx][:high].to_f
            next unless hi > level && close < level

            return liquidity_event_hash(
              side: :buy_side,
              level: level,
              pivot_bar: idx,
              interpretation: :sweep_rejection_lower,
              candle: last
            )
          end

          lows.each do |idx|
            level = candles[idx][:low].to_f
            next unless lo < level && close > level

            return liquidity_event_hash(
              side: :sell_side,
              level: level,
              pivot_bar: idx,
              interpretation: :sweep_rejection_higher,
              candle: last
            )
          end

          nil
        end

        def self.liquidity_event_hash(side:, level:, pivot_bar:, interpretation:, candle:)
          o = candle[:open].to_f
          hi = candle[:high].to_f
          lo = candle[:low].to_f
          cl = candle[:close].to_f
          range = hi - lo
          metrics =
            if range.positive?
              grab_vs_sweep(side: side, level: level, open: o, high: hi, low: lo, close: cl, range: range)
            else
              { wick_penetration_ratio: 0.0, close_rejection_depth_ratio: 0.0, event_style: "unclear" }
            end

          {
            side: side,
            level: level,
            pivot_bar: pivot_bar,
            interpretation: interpretation,
            wick_penetration_ratio: metrics[:wick_penetration_ratio],
            close_rejection_depth_ratio: metrics[:close_rejection_depth_ratio],
            event_style: metrics[:event_style]
          }
        end

        def self.grab_vs_sweep(side:, level:, open:, high:, low:, close:, range:)
          if side == :buy_side
            wick_penetration_ratio = ((high - level) / range).round(3)
            close_rejection_depth_ratio = ((level - close) / range).round(3)
          else
            wick_penetration_ratio = ((level - low) / range).round(3)
            close_rejection_depth_ratio = ((close - level) / range).round(3)
          end

          event_style =
            if wick_penetration_ratio >= 0.45 && close_rejection_depth_ratio >= 0.2
              "sweep"
            elsif close_rejection_depth_ratio < 0.3
              "grab"
            else
              "sweep"
            end

          {
            wick_penetration_ratio: wick_penetration_ratio,
            close_rejection_depth_ratio: close_rejection_depth_ratio,
            event_style: event_style
          }
        end
      end
    end
  end
end
