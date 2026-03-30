# frozen_string_literal: true

module Trading
  module MarketData
    Candle = Struct.new(:symbol, :open, :high, :low, :close, :volume,
                        :opened_at, :closed_at, :closed, keyword_init: true)
  end
end
