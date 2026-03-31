# frozen_string_literal: true

module Bot
  module Execution
    class EntryPriceCorrector
      RESOLUTION = "1m"
      WINDOW_BEFORE_SECONDS = 120
      WINDOW_AFTER_SECONDS = 120

      def initialize(market_data:, logger: Rails.logger)
        @market_data = market_data
        @logger = logger
      end

      def corrected_entry_for(position)
        timestamp = entry_timestamp(position)
        return fallback_entry(position) unless timestamp

        close = nearest_close_for(position.symbol, timestamp)
        close&.positive? ? close : fallback_entry(position)
      rescue StandardError => e
        @logger.warn("[EntryPriceCorrector] fallback #{position.symbol}: #{e.message}")
        fallback_entry(position)
      end

      private

      def entry_timestamp(position)
        position.entry_time&.to_i || position.created_at&.to_i
      end

      def fallback_entry(position)
        position.entry_price.to_f
      end

      def nearest_close_for(symbol, timestamp)
        candles = fetch_candles(symbol: symbol, timestamp: timestamp)
        return nil if candles.empty?

        nearest = candles.min_by { |c| (c[:timestamp] - timestamp).abs }
        nearest[:close]
      end

      def fetch_candles(symbol:, timestamp:)
        raw = @market_data.candles(
          {
            "symbol" => symbol,
            "resolution" => RESOLUTION,
            "start" => timestamp - WINDOW_BEFORE_SECONDS,
            "end" => timestamp + WINDOW_AFTER_SECONDS
          }
        )
        normalize(raw)
      end

      def normalize(raw)
        payload = if raw.is_a?(Hash) && raw.key?("result")
                    raw["result"]
                  elsif raw.is_a?(Hash) && raw.key?(:result)
                    raw[:result]
                  else
                    raw
                  end
        return [] unless payload.is_a?(Array)

        payload.map do |c|
          {
            close: (c[:close] || c["close"]).to_f,
            timestamp: (c[:timestamp] || c["timestamp"] || c[:time] || c["time"]).to_i
          }
        end.select { |c| c[:timestamp].positive? }
      end
    end
  end
end
