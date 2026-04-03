# frozen_string_literal: true

module Trading
  module Risk
    # Read-only snapshot of the same gates as RiskManager + PortfolioGuard, for dashboards / paper testing.
    class EntryGatesSummary
      OVERRIDABLE_BLOCKER_CODES = %w[
        kill_switch_halt kill_switch_exposure daily_loss_cap margin_utilization max_concurrent_positions
      ].freeze

      def self.call(session:, portfolio: nil)
        portfolio ||= PortfolioSnapshot.current
        new(session, portfolio).to_h
      end

      def initialize(session, portfolio)
        @session = session
        @portfolio = portfolio
        @guard_state = PortfolioGuard.call(portfolio: portfolio)
      end

      def to_h
        list = blockers
        override = PaperRiskOverride.active?
        gates_would_block = list.any?
        allowed = auto_entry_allowed?(list, override)

        {
          paper_trading: PaperTrading.enabled?,
          execution_mode_label: execution_mode_label,
          trading_session: trading_session_payload,
          kill_switch: portfolio_guard_payload,
          risk_gates: @session ? risk_gates_payload : nil,
          blockers: list,
          paper_risk_override_active: override,
          gates_would_block: gates_would_block,
          auto_entry_allowed: allowed,
          entry_blocked: !allowed
        }
      end

      private

      def auto_entry_allowed?(blocker_list, override_active)
        codes = blocker_list.map { |b| b[:code] }
        return false if codes.include?("no_running_session")
        return true if blocker_list.empty?
        return false unless override_active

        (codes - OVERRIDABLE_BLOCKER_CODES).empty?
      end

      def execution_mode_label
        mode = PaperTrading.execution_mode
        return mode if mode.present?

        PaperTrading.enabled? ? "paper" : "live"
      end

      def trading_session_payload
        return nil unless @session

        {
          id: @session.id,
          strategy: @session.strategy,
          status: @session.status,
          capital_usd: @session.capital.to_f,
          leverage: @session.leverage,
          started_at: @session.started_at&.iso8601(3)
        }
      end

      def portfolio_guard_payload
        {
          state: @guard_state.to_s,
          total_pnl_usd: @portfolio.total_pnl.to_f,
          total_exposure_usd: @portfolio.total_exposure.to_f,
          halt_if_pnl_at_or_below_usd: PortfolioGuard::MAX_DAILY_LOSS.to_f,
          exposure_must_stay_below_usd: PortfolioGuard::MAX_EXPOSURE.to_f,
          blocks_new_entries: @guard_state != :ok
        }
      end

      def risk_gates_payload
        return nil unless @session

        {
          daily_loss_cap: daily_loss_gate,
          margin_utilization: margin_gate,
          concurrent_positions: concurrent_gate
        }
      end

      def daily_loss_gate
        today_pnl = Trade.sum_effective_pnl_usd(Trade.where("closed_at >= ?", Time.current.beginning_of_day))
        cap_pct = RuntimeConfig.fetch_float("risk.daily_loss_cap_pct", default: 0.05, env_key: "RISK_DAILY_LOSS_CAP_PCT")
        cap_usd = @session.capital.to_f * cap_pct
        {
          today_realized_pnl_usd: today_pnl.round(2),
          loss_cap_usd: cap_usd.round(2),
          loss_cap_pct_of_session_capital: cap_pct,
          blocks_new_entries: today_pnl < -cap_usd
        }
      end

      def margin_gate
        total_margin = Position.active.sum(:margin).to_f
        capital = @session.capital.to_f
        max_u = RuntimeConfig.fetch_float("risk.max_margin_utilization", default: 0.40, env_key: "RISK_MAX_MARGIN_UTILIZATION")
        if capital <= 0
          return {
            margin_used_usd: total_margin.round(2),
            utilization_pct: 0.0,
            max_utilization_pct: (max_u * 100).round(2),
            blocks_new_entries: false,
            note: "session capital is zero — margin gate skipped"
          }
        end

        util = total_margin / capital
        {
          margin_used_usd: total_margin.round(2),
          utilization_pct: (util * 100).round(2),
          max_utilization_pct: (max_u * 100).round(2),
          blocks_new_entries: util >= max_u
        }
      end

      def concurrent_gate
        count = Position.active.count
        max_p = RuntimeConfig.fetch_integer("risk.max_concurrent_positions", default: 5, env_key: "RISK_MAX_CONCURRENT_POSITIONS")
        {
          current: count,
          max: max_p,
          blocks_new_entries: count >= max_p
        }
      end

      def blockers
        reasons = []
        if @session.nil?
          reasons << {
            code: "no_running_session",
            message: "No trading session is running — the strategy runner is not attached to an active session."
          }
        end

        reasons.concat(portfolio_guard_blockers)
        reasons.concat(session_risk_blockers) if @session
        reasons
      end

      def portfolio_guard_blockers
        case @guard_state
        when :halt_trading
          [{
            code: "kill_switch_halt",
            message: "Portfolio guard: trading halted (portfolio PnL #{@portfolio.total_pnl.to_f.round(2)} USD at or below #{PortfolioGuard::MAX_DAILY_LOSS.to_f} USD)."
          }]
        when :block_new_trades
          [{
            code: "kill_switch_exposure",
            message: "Portfolio guard: new entries blocked (exposure #{@portfolio.total_exposure.to_f.round(2)} USD ≥ cap #{PortfolioGuard::MAX_EXPOSURE.to_f} USD)."
          }]
        else
          []
        end
      end

      def session_risk_blockers
        g = risk_gates_payload
        out = []
        if g[:daily_loss_cap][:blocks_new_entries]
          d = g[:daily_loss_cap]
          out << {
            code: "daily_loss_cap",
            message: "Daily loss cap exceeded (#{d[:today_realized_pnl_usd]} USD vs floor -#{d[:loss_cap_usd]} USD)."
          }
        end

        if g[:margin_utilization][:blocks_new_entries]
          m = g[:margin_utilization]
          out << {
            code: "margin_utilization",
            message: "Margin utilization #{m[:utilization_pct]}% exceeds max #{m[:max_utilization_pct]}%."
          }
        end

        if g[:concurrent_positions][:blocks_new_entries]
          c = g[:concurrent_positions]
          out << {
            code: "max_concurrent_positions",
            message: "Max concurrent positions reached (#{c[:current]}/#{c[:max]})."
          }
        end

        out
      end
    end
  end
end
