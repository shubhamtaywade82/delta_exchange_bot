# frozen_string_literal: true

module Trading
  module MarketData
    class OhlcvFetcher
      DEFAULT_LIMIT = 200

      INTERVAL_SECONDS = {
        "1m"  => 60,
        "5m"  => 300,
        "15m" => 900,
        "1h"  => 3600
      }.freeze

      def initialize(client:)
        @client = client
      end

      # Returns array of Candle structs from oldest to newest.
      def fetch(symbol:, resolution:, limit: DEFAULT_LIMIT)
        raw = @client.get_ohlcv(symbol: symbol, resolution: resolution, limit: limit)
        interval = INTERVAL_SECONDS.fetch(resolution, 60)

        raw.map do |r|
          Candle.new(
            symbol:    symbol,
            open:      r[:open].to_f,
            high:      r[:high].to_f,
            low:       r[:low].to_f,
            close:     r[:close].to_f,
            volume:    r[:volume].to_f,
            opened_at: Time.at(r[:time].to_i),
            closed_at: Time.at(r[:time].to_i + interval),
            closed:    true
          )
        end
      rescue => e
        Rails.logger.error("[OhlcvFetcher] Failed for #{symbol}/#{resolution}: #{e.message}")
        []
      end
    end
  end
end
