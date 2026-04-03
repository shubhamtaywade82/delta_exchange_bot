# frozen_string_literal: true

module Trading
  module Analysis
    # HH / HL / LH / LL labels on alternating swing pivots + coarse trend_type.
    module SmcSwingStructure
      extend self

      def analyze(candles, swing: 3)
        return default_empty if candles.size < swing * 4

        highs = Bot::Strategy::Indicators::SwingFractal.pivot_high_indices(candles, left: swing, right: swing)
        lows = Bot::Strategy::Indicators::SwingFractal.pivot_low_indices(candles, left: swing, right: swing)
        events = []
        highs.each { |i| events << { index: i, kind: "high", price: candles[i][:high].to_f } }
        lows.each { |i| events << { index: i, kind: "low", price: candles[i][:low].to_f } }
        events.sort_by! { |e| e[:index] }

        last_high = nil
        last_low = nil
        labeled = []
        events.each do |e|
          if e[:kind] == "high"
            label =
              if last_high.nil?
                nil
              elsif e[:price] > last_high
                "HH"
              else
                "LH"
              end
            last_high = e[:price]
            labeled << e.merge(structure_label: label)
          else
            label =
              if last_low.nil?
                nil
              elsif e[:price] > last_low
                "HL"
              else
                "LL"
              end
            last_low = e[:price]
            labeled << e.merge(structure_label: label)
          end
        end

        recent = labeled.last(12)
        {
          "recent_swings" => recent.map { |x| serialize_swing(x) },
          "trend_type" => infer_trend(recent)
        }
      end

      def default_empty
        { "recent_swings" => [], "trend_type" => "unknown" }
      end

      def serialize_swing(e)
        {
          "bar_index" => e[:index],
          "kind" => e[:kind],
          "price" => e[:price],
          "structure_label" => e[:structure_label]
        }
      end

      def infer_trend(recent)
        labs = recent.filter_map { |x| x[:structure_label] }
        return "range" if labs.size < 2

        bull = labs.count { |l| %w[HH HL].include?(l) }
        bear = labs.count { |l| %w[LH LL].include?(l) }
        if bull > bear + 1
          "uptrend"
        elsif bear > bull + 1
          "downtrend"
        else
          "range"
        end
      end
    end
  end
end
