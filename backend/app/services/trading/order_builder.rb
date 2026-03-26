# frozen_string_literal: true

module Trading
  class OrderBuilder
    def self.build(signal, session:)
      new(signal, session).build
    end

    def initialize(signal, session)
      @signal  = signal
      @session = session
    end

    def build
      {
        trading_session_id: @session.id,
        symbol:             @signal.symbol,
        side:               @signal.side,
        size:               calculate_size,
        price:              @signal.entry_price,
        order_type:         "limit_order",
        status:             "pending",
        idempotency_key:    IdempotencyGuard.key(
          symbol:    @signal.symbol,
          side:      @signal.side,
          timestamp: @signal.candle_timestamp.to_i
        )
      }
    end

    private

    def calculate_size
      return 1 unless @session.capital.present? && @signal.entry_price.to_f.positive?

      capital          = @session.capital.to_f
      leverage         = (@session.leverage || 10).to_f
      entry            = @signal.entry_price.to_f
      risk_pct         = 0.015  # 1.5% risk per trade

      margin_per_trade = capital * risk_pct
      notional         = margin_per_trade * leverage
      lots             = (notional / entry).floor
      [lots, 1].max
    end
  end
end
