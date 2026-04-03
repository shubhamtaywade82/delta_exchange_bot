# frozen_string_literal: true

module Trading
  module Analysis
    # External (wide) vs internal (tight) BOS — same close-beyond rule, different swing memory.
    module SmcInternalExternalStructure
      extend self

      def snapshot(candles, external_lookback:, internal_lookback:)
        internal_lb = [internal_lookback, 3].max
        ext_series = Bot::Strategy::Indicators::BOS.compute(candles, swing_lookback: external_lookback)
        int_series = Bot::Strategy::Indicators::BOS.compute(candles, swing_lookback: internal_lb)
        ext = ext_series.last
        int = int_series.last

        {
          "external" => serialize_bos(ext),
          "internal" => serialize_bos(int),
          "divergent" => ext[:direction] != int[:direction] && ext[:direction].present? && int[:direction].present?
        }
      end

      def serialize_bos(row)
        return nil unless row

        {
          "direction" => row[:direction]&.to_s,
          "level" => row[:level],
          "confirmed" => row[:confirmed]
        }
      end
    end
  end
end
