# frozen_string_literal: true

module Trading
  module Analysis
    # ATR(14) proxy and range expansion vs ATR.
    module SmcVolatilitySnapshot
      PERIOD = Integer(ENV.fetch("ANALYSIS_ATR_PERIOD", "14"))

      extend self

      def snapshot(candles)
        return nil if candles.size < PERIOD + 2

        trs = []
        (1...candles.size).each do |i|
          trs << true_range(candles[i - 1], candles[i])
        end
        tail = trs.last(PERIOD)
        atr = tail.sum / tail.size.to_f
        last = candles.last
        last_range = last[:high].to_f - last[:low].to_f
        ratio = atr.positive? ? (last_range / atr).round(2) : 0.0

        {
          "atr" => atr,
          "last_range" => last_range,
          "range_vs_atr" => ratio,
          "expansion_hint" => ratio >= 1.25,
          "contraction_hint" => ratio <= 0.65
        }
      end

      def true_range(prev, cur)
        h = cur[:high].to_f
        l = cur[:low].to_f
        pc = prev[:close].to_f
        [h - l, (h - pc).abs, (l - pc).abs].max
      end
    end
  end
end
