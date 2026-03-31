# frozen_string_literal: true

module Bot
  module Strategy
    Signal = Struct.new(:symbol, :side, :entry_price, :candle_ts, :signal_id, keyword_init: true) do
      def long?  = side == :long
      def short? = side == :short
    end
  end
end
