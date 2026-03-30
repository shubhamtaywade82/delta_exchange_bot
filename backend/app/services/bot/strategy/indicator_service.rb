# frozen_string_literal: true

# This service provides a unified interface for technical analysis indicators
# using the newly integrated gems.
module Bot
  module Strategy
    class IndicatorService
      class << self
        def rsi(candles, period: 14, source: :technical_analysis)
          case source
          when :ruby_technical_analysis
            data = candles.map { |c| c[:close].to_f }
            [RubyTechnicalAnalysis::RelativeStrengthIndex.call(series: data, period: period)]
          when :technical_analysis
            data = transform(candles)
            # Must specify price_key: :close as it defaults to :value
            result = TechnicalAnalysis::Rsi.calculate(data, period: period, price_key: :close)
            result.map(&:rsi).reverse
          else
            raise ArgumentError, "Unknown source: #{source}"
          end
        end

        def sma(candles, period: 14, source: :technical_analysis)
          case source
          when :ruby_technical_analysis
            data = candles.map { |c| c[:close].to_f }
            [RubyTechnicalAnalysis::SimpleMovingAverage.call(series: data, period: period)]
          when :technical_analysis
            data = transform(candles)
            result = TechnicalAnalysis::Sma.calculate(data, period: period, price_key: :close)
            result.map(&:sma).reverse
          else
            raise ArgumentError, "Unknown source: #{source}"
          end
        end

        private

        def transform(candles)
          candles.map do |c|
            {
              open:   c[:open].to_f,
              high:   c[:high].to_f,
              low:    c[:low].to_f,
              close:  c[:close].to_f,
              volume: c[:volume].to_f,
              date_time: c[:timestamp] || Time.now
            }
          end
        end
      end
    end
  end
end
