# frozen_string_literal: true

module Trading
  class RiskManager
    class RiskError < StandardError; end

    MAX_CONCURRENT_POSITIONS = 5
    MAX_MARGIN_UTILIZATION   = 0.40  # 40%
    DAILY_LOSS_CAP_PCT       = 0.05  # 5% of session capital

    def self.validate!(signal, session:)
      new(signal, session).validate!
    end

    def initialize(signal, session)
      @signal  = signal
      @session = session
    end

    def validate!
      check_max_concurrent_positions!
      check_margin_utilization!
      check_daily_loss_cap!
    end

    private

    def check_max_concurrent_positions!
      count = Position.where(status: "open").count
      raise RiskError, "max concurrent positions reached (#{count}/#{MAX_CONCURRENT_POSITIONS})" if
        count >= MAX_CONCURRENT_POSITIONS
    end

    def check_margin_utilization!
      total_margin = Position.where(status: "open").sum(:margin).to_f
      capital      = @session.capital.to_f
      return if capital.zero?

      utilization = total_margin / capital
      raise RiskError, "margin utilization #{(utilization * 100).round(1)}% exceeds #{(MAX_MARGIN_UTILIZATION * 100).to_i}% cap" if
        utilization >= MAX_MARGIN_UTILIZATION
    end

    def check_daily_loss_cap!
      today_pnl = Trade.where("closed_at >= ?", Time.current.beginning_of_day).sum(:pnl_usd).to_f
      cap       = @session.capital.to_f * DAILY_LOSS_CAP_PCT
      raise RiskError, "daily loss cap exceeded (#{today_pnl.round(2)} USD vs cap -#{cap.round(2)} USD)" if
        today_pnl < -cap
    end
  end
end
