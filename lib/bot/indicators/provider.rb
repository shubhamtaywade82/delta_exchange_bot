# frozen_string_literal: true

require "ruby-technical-analysis"
require "technical-analysis"

module Bot
  module Indicators
    # Unified Provider for technical analysis indicators.
    # It wraps multiple gems to provide a consistent API and handles data transformation.
    class Provider
      DEFAULT_PERIOD = 14

      class << self
        # RSI Calculation
        # @param candles [Array<Hash>] array of candle hashes with :close key
        # @param period [Integer] lookback period
        # @param source [Symbol] :ruby_technical_analysis or :technical_analysis
        # @return [Array<Float>] RSI values
        def rsi(candles, period: DEFAULT_PERIOD, source: :technical_analysis)
          case source
          when :ruby_technical_analysis
            # expects array of floats
            data = candles.map { |c| c[:close].to_f }
            [RubyTechnicalAnalysis::RelativeStrengthIndex.call(series: data, period: period)]
          when :technical_analysis
            # expects array of hashes with price data
            data = transform_for_intrinio(candles)
            # Must specify price_key: :close as it defaults to :value
            result = TechnicalAnalysis::Rsi.calculate(data, period: period, price_key: :close)
            result.map(&:rsi).reverse # Gem returns in reverse chronological order
          else
            raise ArgumentError, "Unknown source: #{source}"
          end
        end

        # SMA Calculation
        def sma(candles, period: DEFAULT_PERIOD, source: :technical_analysis)
          case source
          when :ruby_technical_analysis
            data = candles.map { |c| c[:close].to_f }
            [RubyTechnicalAnalysis::SimpleMovingAverage.call(series: data, period: period)]
          when :technical_analysis
            data = transform_for_intrinio(candles)
            result = TechnicalAnalysis::Sma.calculate(data, period: period, price_key: :close)
            result.map(&:sma).reverse
          else
            raise ArgumentError, "Unknown source: #{source}"
          end
        end

        private

        def transform_for_intrinio(candles)
          candles.map do |c|
            {
              open:   c[:open].to_f,
              high:   c[:high].to_f,
              low:    c[:low].to_f,
              close:  c[:close].to_f,
              volume: c[:volume].to_f,
              date_time: c[:timestamp] || Time.now # Some indicators might need this
            }
          end
        end
      end
    end
  end
end
