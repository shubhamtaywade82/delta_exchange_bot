# frozen_string_literal: true

module Trading
  module Analysis
    # Multi-timeframe last-bar payload from {Trading::Analysis::SmcConfluence::Engine}
    # (Pine `smc_confluence.pine` parity). JSON-serializable for APIs, Redis, and Ollama.
    class SmcConfluenceMtf
      DEFAULT_RESOLUTIONS = %w[4h 1h 5m].freeze

      class << self
        # Fetches candles per resolution (Delta REST) and builds the MTF payload.
        def build(symbol:, market_data:, config:, resolutions: DEFAULT_RESOLUTIONS,
                  configuration: SmcConfluence::Configuration.new)
          tf_candles = resolutions.to_h do |res|
            rows = HistoricalCandles.fetch(
              market_data: market_data,
              config: config,
              symbol: symbol,
              resolution: res
            )
            [ res, rows ]
          end
          from_timeframe_candles(
            symbol: symbol,
            timeframe_candles: tf_candles,
            configuration: configuration
          )
        end

        # Uses already-loaded candle arrays (oldest → newest), keyed by resolution string.
        def from_timeframe_candles(symbol:, timeframe_candles:, configuration: SmcConfluence::Configuration.new)
          new(
            symbol: symbol,
            timeframe_candles: timeframe_candles,
            configuration: configuration
          ).to_h
        end
      end

      def initialize(symbol:, timeframe_candles:, configuration:)
        @symbol = symbol
        @timeframe_candles = timeframe_candles.transform_keys(&:to_s)
        @configuration = configuration
      end

      def to_h
        timeframes = {}
        alignment = {
          "long_signal" => {},
          "short_signal" => {},
          "structure_bias" => {},
          "long_score" => {},
          "short_score" => {},
          "choch_bull" => {},
          "choch_bear" => {},
          "liq_sweep_bull" => {},
          "liq_sweep_bear" => {},
          "pdh_sweep" => {},
          "pdl_sweep" => {}
        }

        @timeframe_candles.each do |resolution, candles|
          next unless candles.is_a?(Array) && candles.any?

          series = SmcConfluence::Engine.run(candles, configuration: @configuration)
          last = series.last
          next unless last

          raw = last.serialize
          timeframes[resolution] = {
            "resolution" => resolution,
            "candle_count" => candles.size,
            "last_bar_at" => Time.zone.at(candles.last[:timestamp]).utc.iso8601,
            "last_close" => round_price(candles.last[:close]),
            "confluence" => round_confluence(raw)
          }

          alignment["long_signal"][resolution] = last.long_signal
          alignment["short_signal"][resolution] = last.short_signal
          alignment["structure_bias"][resolution] = last.structure_bias
          alignment["long_score"][resolution] = last.long_score
          alignment["short_score"][resolution] = last.short_score
          alignment["choch_bull"][resolution] = last.choch_bull
          alignment["choch_bear"][resolution] = last.choch_bear
          alignment["liq_sweep_bull"][resolution] = last.liq_sweep_bull
          alignment["liq_sweep_bear"][resolution] = last.liq_sweep_bear
          alignment["pdh_sweep"][resolution] = last.pdh_sweep
          alignment["pdl_sweep"][resolution] = last.pdl_sweep
        end

        {
          "schema_version" => 1,
          "kind" => "smc_confluence_mtf",
          "symbol" => @symbol,
          "generated_at_utc" => Time.current.utc.iso8601,
          "source" => "Trading::Analysis::SmcConfluence::Engine",
          "timeframes" => timeframes,
          "alignment" => alignment,
          "notes" => [
            "Each timeframe confluence object is the last closed bar in the fetched window (Pine-parity scoring).",
            "PDH/PDL populate after a UTC calendar day rollover within the window.",
            "Legacy SMC (BOS/CHOCH modules) remains under digest smc_by_timeframe; this object is the confluence engine only."
          ]
        }
      end

      private

      def round_confluence(h)
        return nil unless h.is_a?(Hash)

        c = h.stringify_keys
        %w[pdh pdl poc vah val atr14].each do |key|
          c[key] = round_price(c[key]) if c.key?(key)
        end
        %w[tl_bear_break tl_bull_break pdh_sweep pdl_sweep].each do |key|
          c[key] = c[key] ? true : false if c.key?(key)
        end
        c
      end

      def round_price(value)
        return nil if value.nil?

        value.to_d.round(4).to_f
      end
    end
  end
end
