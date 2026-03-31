# frozen_string_literal: true

module Trading
  module MarketData
    class CandleSeries
      MAX_CANDLES = 2_000
      @candles = []

      class << self
        def load(candles)
          @candles = Array(candles).dup
          trim!
        end

        def add(candle)
          @candles ||= []
          @candles << candle
          trim!
          candle
        end

        def all
          (@candles || []).dup
        end

        def size
          (@candles || []).size
        end

        def closes(last_n)
          all.last(last_n).map { |candle| candle.close.to_f }
        end

        def reset!
          @candles = []
        end

        private

        def trim!
          overflow = size - MAX_CANDLES
          return if overflow <= 0

          @candles.shift(overflow)
        end
      end
    end
  end
end
