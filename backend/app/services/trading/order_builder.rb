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
      risk_pct = bounded_risk_pct(base_risk_pct * adaptive_risk_multiplier * bias_adjustment_factor)

      margin_per_trade = capital * risk_pct
      notional = margin_per_trade * leverage
      lots = (notional / entry).floor
      [lots, 1].max
    end

    def base_risk_pct
      0.015
    end

    def bounded_risk_pct(value)
      [[value, 0.05].min, 0.005].max
    end

    def adaptive_risk_multiplier
      return 1.0 unless adaptive_signal?

      multiplier = adaptive_context.dig("ai_config", "risk_multiplier")
      Float(multiplier)
    rescue ArgumentError, TypeError
      1.0
    end

    def bias_adjustment_factor
      return 1.0 unless adaptive_signal?

      bias = Float(adaptive_context["bias"] || adaptive_context.dig("ai_config", "bias") || 0.0)
      directional_bias = @signal.side.to_s.in?(%w[buy long]) ? bias : -bias
      [[1.0 + (directional_bias * 0.2), 1.2].min, 0.8].max
    rescue ArgumentError, TypeError
      1.0
    end

    def adaptive_signal?
      @signal.strategy.to_s.start_with?("adaptive:")
    end

    def adaptive_context
      @adaptive_context ||= begin
        context = Rails.cache.read("adaptive:entry_context:#{@signal.symbol}")
        context.is_a?(Hash) ? context.deep_stringify_keys : {}
      end
    end
  end
end
