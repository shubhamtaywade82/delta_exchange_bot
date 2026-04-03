# frozen_string_literal: true

module Trading
  module Analysis
    # UTC session high/low liquidity (Asian / London / New York style buckets for crypto).
    module SmcSessionRanges
      extend self

      def snapshot(candles)
        acc = Hash.new { |h, k| h[k] = { highs: [], lows: [] } }
        candles.each do |c|
          hour = Time.zone.at(c[:timestamp]).utc.hour
          name = session_name(hour)
          acc[name][:highs] << c[:high].to_f
          acc[name][:lows] << c[:low].to_f
        end

        acc.transform_values do |v|
          next nil if v[:highs].empty?

          {
            "high" => v[:highs].max,
            "low" => v[:lows].min
          }
        end.compact
      end

      def session_name(utc_hour)
        case utc_hour
        when 0...8 then "asian"
        when 8...13 then "london"
        when 13...22 then "new_york"
        else "after_hours"
        end
      end
    end
  end
end
