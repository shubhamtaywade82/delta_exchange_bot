# frozen_string_literal: true

module Trading
  class OrderBuilder
    class SizingError < StandardError; end

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
        portfolio_id: @session.portfolio_id,
        position_id: @position.id,
        symbol: @signal.symbol,
        side: side,
        size: calculate_size,
        price: @signal.entry_price,
        order_type: "limit_order",
        status: "created",
        client_order_id: SecureRandom.uuid,
        idempotency_key: IdempotencyGuard.key_for_signal(@signal)
      }
    end

    private

    def map_side(strategy_side)
      IdempotencyGuard.exchange_side(strategy_side)
    end

    def calculate_size
      return 1 unless @session.capital.present? && @signal.entry_price.to_f.positive?

      entry = @signal.entry_price.to_f
      contract_value = Trading::Risk::PositionLotSize.multiplier_for(@position).to_f
      stop_price = effective_stop_price(entry)

      balance_inr = @session.capital.to_d * Finance::UsdInrRate.current
      risk_pct = bounded_risk_pct(base_risk_pct * adaptive_risk_multiplier * bias_adjustment_factor)

      rate = Finance::UsdInrRate.current
      result = Finance::PositionSizer.compute!(
        balance_inr: balance_inr.to_f,
        risk_percent: risk_pct,
        entry_price: entry,
        stop_price: stop_price,
        contract_value: contract_value,
        usd_inr: rate,
        leverage: effective_leverage,
        margin_wallet_usd: margin_wallet_usd,
        position_size_limit: product_position_size_limit
      )

      raise SizingError, sizing_failure_detail(result) if result.contracts.zero?

      result.contracts
    end

    def effective_leverage
      lev = @position.leverage.to_i
      lev = @session.leverage.to_i if lev <= 0
      lev.positive? ? lev : 1
    end

    def margin_wallet_usd
      @session.portfolio.reload.available_balance.to_f
    end

    def product_position_size_limit
      PaperProductSnapshot.find_by(symbol: @position.symbol.to_s)&.position_size_limit
    end

    def sizing_failure_detail(result)
      if result.qty_risk.positive? && result.qty_margin.to_i < result.qty_risk
        "sizing capped to zero by margin or product limit (qty_risk=#{result.qty_risk}, " \
          "qty_margin=#{result.qty_margin}, stop_distance=#{result.stop_distance}, " \
          "risk_per_contract=#{result.risk_per_contract})"
      else
        "risk budget yields zero contracts (stop_distance=#{result.stop_distance}, " \
          "risk_per_contract=#{result.risk_per_contract})"
      end
    end

    def effective_stop_price(entry)
      explicit = @signal.respond_to?(:stop_price) ? @signal.stop_price : nil
      return explicit.to_f if explicit.present?

      trail_pct = Trading::RuntimeConfig.fetch_float(
        "risk.trail_pct_for_sizing",
        default: 1.5,
        env_key: "RISK_TRAIL_PCT_FOR_SIZING"
      )
      trail_distance = entry * (trail_pct / 100.0)

      case @signal.side.to_s.downcase
      when "long", "buy"
        entry - trail_distance
      when "short", "sell"
        entry + trail_distance
      else
        entry - trail_distance
      end
    end

    def base_risk_pct
      0.015
    end

    def bounded_risk_pct(value)
      [ [ value, 0.05 ].min, 0.005 ].max
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
      [ [ 1.0 + (directional_bias * 0.2), 1.2 ].min, 0.8 ].max
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
