# frozen_string_literal: true

module Trading
  module Analysis
    # Lightweight classical PA tags on the last closed bar (vs prior).
    module SmcPriceActionSnapshot
      extend self

      def last_bar(candles)
        return nil if candles.size < 2

        a = candles[-2]
        b = candles[-1]
        body_b = (b[:close].to_f - b[:open].to_f).abs
        range_b = b[:high].to_f - b[:low].to_f

        bullish_engulf = b[:close].to_f > b[:open].to_f && a[:close].to_f < a[:open].to_f &&
                         b[:open].to_f <= a[:close].to_f && b[:close].to_f >= a[:open].to_f
        bearish_engulf = b[:close].to_f < b[:open].to_f && a[:close].to_f > a[:open].to_f &&
                         b[:open].to_f >= a[:close].to_f && b[:close].to_f <= a[:open].to_f

        inside = b[:high].to_f <= a[:high].to_f && b[:low].to_f >= a[:low].to_f
        pin = pin_bar?(b, range_b)

        {
          "bullish_engulfing" => bullish_engulf,
          "bearish_engulfing" => bearish_engulf,
          "inside_bar" => inside,
          "pin_bar" => pin,
          "doji_hint" => range_b.positive? && body_b / range_b < 0.12
        }
      end

      def pin_bar?(b, range)
        return false unless range.positive?

        o = b[:open].to_f
        h = b[:high].to_f
        l = b[:low].to_f
        cl = b[:close].to_f
        body = (cl - o).abs
        upper = h - [o, cl].max
        lower = [o, cl].min - l
        long_wick = [upper, lower].max
        long_wick >= body * 2.0 && body / range < 0.35
      end
    end
  end
end
