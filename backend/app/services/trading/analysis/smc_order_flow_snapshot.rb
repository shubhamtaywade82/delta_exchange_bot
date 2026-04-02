# frozen_string_literal: true

module Trading
  module Analysis
    # Displacement proxy: body/range, volume vs short MA — no tape / delta.
    module SmcOrderFlowSnapshot
      VOLUME_WINDOW = 20

      extend self

      def last_bar(candles)
        return nil if candles.empty?

        c = candles.last
        o = c[:open].to_f
        h = c[:high].to_f
        l = c[:low].to_f
        cl = c[:close].to_f
        range = h - l
        body = (cl - o).abs
        body_ratio = range.positive? ? (body / range).round(3) : 0.0

        vol = c[:volume].to_f
        tail = candles.last([candles.size, VOLUME_WINDOW].min)
        avg_vol = tail.sum { |x| x[:volume].to_f } / tail.size.to_f
        volume_vs_avg = avg_vol.positive? ? (vol / avg_vol).round(2) : 1.0

        {
          "body_ratio" => body_ratio,
          "volume_vs_avg" => volume_vs_avg,
          "imbalance_candle_hint" => body_ratio >= 0.62 && volume_vs_avg >= 1.15,
          "displacement_hint" => body_ratio >= 0.68 && range.positive?
        }
      end
    end
  end
end
