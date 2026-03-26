# frozen_string_literal: true

module Trading
  module MarketData
    class CandleSeries
      MAX_CANDLES = 500

      @candles = []
      @mutex   = Mutex.new

      class << self
        def load(candles)
          @mutex.synchronize { @candles = candles.dup }
        end

        def add(candle)
          @mutex.synchronize do
            @candles << candle
            @candles.shift if @candles.size > MAX_CANDLES
          end
        end

        def all
          @mutex.synchronize { @candles.dup }
        end

        def closes(n = nil)
          series = all.map(&:close)
          n ? series.last(n) : series
        end

        def last_candle
          all.last
        end

        def size
          @mutex.synchronize { @candles.size }
        end

        def reset!
          @mutex.synchronize { @candles = [] }
        end
      end
    end
  end
end
