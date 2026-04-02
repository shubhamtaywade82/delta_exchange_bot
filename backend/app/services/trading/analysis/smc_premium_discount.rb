# frozen_string_literal: true

module Trading
  module Analysis
    # Premium / discount / equilibrium vs recent swing range (0–100 fib-style position of close).
    module SmcPremiumDiscount
      LOOKBACK_BARS = Integer(ENV.fetch("ANALYSIS_PREMIUM_DISCOUNT_LOOKBACK", "60"))

      extend self

      def position(candles)
        return nil if candles.empty?

        slice = candles.last([candles.size, LOOKBACK_BARS].min)
        hi = slice.map { |c| c[:high].to_f }.max
        lo = slice.map { |c| c[:low].to_f }.min
        close = candles.last[:close].to_f
        range = hi - lo
        return nil if range <= 0

        pct = ((close - lo) / range * 100.0).round(2)
        zone =
          if pct < 45.0
            "discount"
          elsif pct > 55.0
            "premium"
          else
            "equilibrium"
          end

        {
          "range_high" => hi,
          "range_low" => lo,
          "close_percent_in_range" => pct,
          "zone" => zone,
          "long_filter_ok" => zone != "premium",
          "short_filter_ok" => zone != "discount"
        }
      end
    end
  end
end
