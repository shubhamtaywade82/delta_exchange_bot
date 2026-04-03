# frozen_string_literal: true

require "timeout"

module Trading
  module Analysis
    # Fetches normalized OHLCV from Delta REST for SMC / structure snapshots (no strategy side effects).
    module HistoricalCandles
      FETCH_TIMEOUT_S = Float(ENV.fetch("ANALYSIS_CANDLE_FETCH_TIMEOUT_S", "20"))

      module_function

      def fetch(market_data:, config:, symbol:, resolution:)
        end_ts = Time.now.to_i
        start_ts = end_ts - (resolution_to_seconds(resolution) * config.candles_lookback)
        raw = Timeout.timeout(FETCH_TIMEOUT_S) do
          market_data.candles(
            "symbol" => symbol,
            "resolution" => resolution,
            "start" => start_ts,
            "end" => end_ts
          )
        end
        normalize_candles(raw)
      rescue Timeout::Error
        Rails.logger.warn("[Analysis::HistoricalCandles] timeout #{symbol} #{resolution}")
        []
      rescue StandardError => e
        Rails.logger.warn("[Analysis::HistoricalCandles] #{symbol} #{resolution}: #{e.message}")
        []
      end

      def resolution_to_seconds(resolution)
        match = resolution.to_s.match(/(\d+)([smhdw])/)
        return resolution.to_i * 60 unless match

        value = match[1].to_i
        case match[2]
        when "s" then value
        when "m" then value * 60
        when "h" then value * 3600
        when "d" then value * 86_400
        when "w" then value * 604_800
        else value * 60
        end
      end

      def normalize_candles(raw)
        candles_payload =
          if raw.is_a?(Hash) && raw.key?("result")
            raw["result"]
          elsif raw.is_a?(Hash) && raw.key?(:result)
            raw[:result]
          else
            raw
          end
        return [] unless candles_payload.is_a?(Array)

        candles_payload.map do |c|
          {
            open: (c[:open] || c["open"]).to_f,
            high: (c[:high] || c["high"]).to_f,
            low: (c[:low] || c["low"]).to_f,
            close: (c[:close] || c["close"]).to_f,
            volume: (c[:volume] || c["volume"]).to_f,
            timestamp: (c[:timestamp] || c["timestamp"] || c[:time] || c["time"]).to_i
          }
        end.sort_by { |c| c[:timestamp] }
      end
    end
  end
end
