# frozen_string_literal: true

module Trading
  class OrderBuilder
    def self.build(signal, session:, position:)
      new(signal, session, position).build
    end

    def initialize(signal, session, position)
      @signal = signal
      @session = session
      @position = position
    end

    def build
      side = map_side(@signal.side)
      {
        trading_session_id: @session.id,
        position_id: @position.id,
        symbol: @signal.symbol,
        side: side,
        size: calculate_size,
        price: @signal.entry_price,
        order_type: "limit_order",
        status: "created",
        client_order_id: SecureRandom.uuid,
        idempotency_key: IdempotencyGuard.key(
          symbol: @signal.symbol,
          side: side,
          timestamp: @signal.candle_timestamp.to_i
        )
      }
    end

    private

    def map_side(strategy_side)
      case strategy_side.to_sym
      when :long, :buy then "buy"
      when :short, :sell then "sell"
      else strategy_side.to_s
      end
    end

    def calculate_size
      return 1 unless @session.capital.present? && @signal.entry_price.to_f.positive?

      capital = @session.capital.to_f
      leverage = (@session.leverage || 10).to_f
      entry = @signal.entry_price.to_f
      risk_pct = 0.015

      margin_per_trade = capital * risk_pct
      notional = margin_per_trade * leverage
      lots = (notional / entry).floor
      [lots, 1].max
    end
  end
end
