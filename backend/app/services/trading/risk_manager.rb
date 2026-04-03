# frozen_string_literal: true

module Trading
  class RiskManager
    class RiskError < StandardError; end

    def self.validate!(signal, session:)
      new(signal, session).validate!
    end

    def initialize(signal, session)
      @signal  = signal
      @session = session
    end

    def validate!
      return if PaperRiskOverride.active?

      check_max_concurrent_positions!
      check_pyramiding!
      check_margin_utilization!
      check_daily_loss_cap!
    end

    private

    def active_positions_for_session_portfolio
      Position.active_for_portfolio(@session.portfolio_id)
    end

    def check_max_concurrent_positions!
      count = active_positions_for_session_portfolio.count
      max_positions = Trading::RuntimeConfig.fetch_integer("risk.max_concurrent_positions", default: 5, env_key: "RISK_MAX_CONCURRENT_POSITIONS")
      raise RiskError, "max concurrent positions reached (#{count}/#{max_positions})" if count >= max_positions
    end

    def check_pyramiding!
      return if Trading::RuntimeConfig.fetch_boolean(
        "risk.allow_pyramiding",
        default: true,
        env_key: "RISK_ALLOW_PYRAMIDING"
      )

      sym = @signal.symbol.to_s
      side_keys = Trading::ExecutionEngine.active_position_side_keys(@signal.side)
      exists = active_positions_for_session_portfolio.where(symbol: sym, side: side_keys).exists?
      return unless exists

      raise RiskError, "pyramiding disabled: active #{sym} position already open for this side"
    end

    def check_margin_utilization!
      total_margin = active_positions_for_session_portfolio.sum(:margin).to_f
      denominator = utilization_denominator_usd
      return if denominator.zero?

      utilization = total_margin / denominator
      max_utilization = Trading::RuntimeConfig.fetch_float("risk.max_margin_utilization", default: 0.40, env_key: "RISK_MAX_MARGIN_UTILIZATION")
      raise RiskError, "margin utilization #{(utilization * 100).round(1)}% exceeds #{(max_utilization * 100).to_i}% cap" if utilization >= max_utilization
    end

    # Realized PnL for the session’s portfolio only (fill-driven Trade rows set portfolio_id).
    def check_daily_loss_cap!
      trades_today = Trade.where("closed_at >= ?", Time.current.beginning_of_day).where(portfolio_id: @session.portfolio_id)
      today_pnl = Trade.sum_effective_pnl_usd(trades_today)
      daily_loss_pct = Trading::RuntimeConfig.fetch_float("risk.daily_loss_cap_pct", default: 0.05, env_key: "RISK_DAILY_LOSS_CAP_PCT")
      cap = utilization_denominator_usd * daily_loss_pct
      raise RiskError, "daily loss cap exceeded (#{today_pnl.round(2)} USD vs cap -#{cap.round(2)} USD)" if
        today_pnl < -cap
    end

    def utilization_denominator_usd
      b = @session.portfolio.reload.balance.to_f
      return b if b.positive?

      @session.capital.to_f
    end
  end
end
