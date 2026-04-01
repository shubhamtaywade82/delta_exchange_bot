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
      check_margin_utilization!
      check_daily_loss_cap!
    end

    private

    def check_max_concurrent_positions!
      count = Position.active.count
      max_positions = Trading::RuntimeConfig.fetch_integer("risk.max_concurrent_positions", default: 5, env_key: "RISK_MAX_CONCURRENT_POSITIONS")
      raise RiskError, "max concurrent positions reached (#{count}/#{max_positions})" if count >= max_positions
    end

    def check_margin_utilization!
      total_margin = Position.active.sum(:margin).to_f
      capital      = @session.capital.to_f
      return if capital.zero?

      utilization = total_margin / capital
      max_utilization = Trading::RuntimeConfig.fetch_float("risk.max_margin_utilization", default: 0.40, env_key: "RISK_MAX_MARGIN_UTILIZATION")
      raise RiskError, "margin utilization #{(utilization * 100).round(1)}% exceeds #{(max_utilization * 100).to_i}% cap" if utilization >= max_utilization
    end

    def check_daily_loss_cap!
      # +pnl_usd+ and +session.capital+ are both treated as USD (see TradingSession).
      today_pnl = Trade.where("closed_at >= ?", Time.current.beginning_of_day).sum(:pnl_usd).to_f
      daily_loss_pct = Trading::RuntimeConfig.fetch_float("risk.daily_loss_cap_pct", default: 0.05, env_key: "RISK_DAILY_LOSS_CAP_PCT")
      cap = @session.capital.to_f * daily_loss_pct
      raise RiskError, "daily loss cap exceeded (#{today_pnl.round(2)} USD vs cap -#{cap.round(2)} USD)" if
        today_pnl < -cap
    end
  end
end
