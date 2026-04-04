# frozen_string_literal: true

module Trading
  module Analysis
    # UTC session high/low liquidity aligned with Pine SMC Confluence defaults:
    # Asia 00:00–08:00, London 08:00–16:00, New York 13:00–21:00 (hours may overlap).
    module SmcSessionRanges
      extend self

      # @return [Hash<String, Hash>] keys: "asian", "london", "new_york", "after_hours"
      def snapshot(candles)
        acc = Hash.new { |h, k| h[k] = { highs: [], lows: [] } }
        candles.each do |c|
          hour = Time.zone.at(c[:timestamp]).utc.hour
          active_sessions(hour).each do |name|
            acc[name][:highs] << c[:high].to_f
            acc[name][:lows] << c[:low].to_f
          end
        end

        acc.transform_values do |v|
          next nil if v[:highs].empty?

          {
            "high" => v[:highs].max,
            "low" => v[:lows].min
          }
        end.compact
      end

      def active_sessions(utc_hour)
        names = []
        names << "asian" if (0...8).cover?(utc_hour)
        names << "london" if (8...16).cover?(utc_hour)
        names << "new_york" if (13...21).cover?(utc_hour)
        names << "after_hours" if names.empty?
        names
      end
    end
  end
end
