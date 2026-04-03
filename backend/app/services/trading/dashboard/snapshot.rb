# frozen_string_literal: true

module Trading
  module Dashboard
    class Snapshot
      USD_INR_FOR_DISPLAY = 85.0
      BROKER_TRADES_LIMIT_DEFAULT = 500
      BROKER_TRADES_LIMIT_MAX = 2000

      def self.call(calendar_day: nil, trades_day: nil, trades_limit: nil)
        new(calendar_day: calendar_day, trades_day: trades_day, trades_limit: trades_limit).to_h
      end

      def initialize(calendar_day:, trades_day:, trades_limit:)
        @calendar_day_raw = calendar_day
        @trades_day_raw = trades_day
        @trades_limit_raw = trades_limit
      end

      def to_h
        running_session = resolve_running_session
        active_positions = dashboard_active_positions(running_session)
        portfolio = Trading::Risk::PortfolioSnapshot.from_positions(active_positions)
        wallet = load_wallet_for_dashboard(portfolio: portfolio, positions: active_positions)
        market = build_market_rows
        trade_totals = Trade.dashboard_pnl_totals
        realized_pnl_usd = dashboard_realized_pnl_usd(running_session, trade_totals)
        ledger_equity_usd = dashboard_ledger_equity_usd(
          wallet: wallet,
          portfolio: portfolio,
          running_session: running_session,
          realized_pnl_usd: realized_pnl_usd
        )
        kpi_totals = dashboard_kpi_trade_totals(running_session, trade_totals)
        daily_pnl = kpi_totals[:daily_pnl].round(2)
        weekly_pnl = kpi_totals[:weekly_pnl].round(2)
        execution_health = build_execution_health
        trade_count = kpi_totals[:trade_count]
        win_rate = trade_count.positive? ? (kpi_totals[:win_count].to_f / trade_count * 100).round(1) : 0
        equity_curve = equity_curve_from_trades
        trades_scope = broker_settled_trades_scope.where(closed_at: trades_day_range)
        trades_total = trades_scope.count
        trades_limit = normalized_trades_limit
        trade_rows = trades_scope.order(closed_at: :desc).limit(trades_limit)
        trade_calendar_days = Trade.broker_settled_calendar_days.map { |d| format_trade_calendar_day(d) }
        signal_activity = build_signal_activity
        operational_state = Trading::Risk::EntryGatesSummary.call(session: running_session, portfolio: portfolio).merge(
          recent_signals: build_recent_signals(limit: 30)
        )

        {
          positions: active_positions.map { |p| position_payload(p) },
          positions_meta: {
            as_of_date: calendar_day_string,
            count: active_positions.size
          },
          trades: trade_rows.map { |t| trade_payload(t) },
          trades_calendar_days: trade_calendar_days,
          trades_meta: {
            total_count: trades_total,
            limit: trades_limit,
            day: trades_day_value.strftime("%Y-%m-%d")
          },
          wallet: wallet,
          stats: {
            total_pnl_usd: realized_pnl_usd,
            total_pnl_inr: (realized_pnl_usd * USD_INR_FOR_DISPLAY).round(0),
            total_equity_usd: ledger_equity_usd,
            total_equity_inr: (ledger_equity_usd * USD_INR_FOR_DISPLAY).round(0),
            win_rate: win_rate,
            daily_pnl: daily_pnl,
            weekly_pnl: weekly_pnl,
            equity_curve: equity_curve
          },
          market: market,
          execution_health: execution_health,
          signal_activity: signal_activity,
          operational_state: operational_state
        }
      end

      private

      # Paper + running session: +PortfolioLedgerEntry+ when present; else balance delta vs session seed;
      # else +Trade+ rows for this portfolio; else legacy +Trade+ rows since +session.started_at+ (nil
      # +portfolio_id+) so the status bar matches TRADE_HISTORY when fills never hit the ledger.
      def dashboard_realized_pnl_usd(running_session, trade_totals)
        return trade_totals[:total_realized].round(2) unless paper_session?(running_session)

        pid = running_session.portfolio_id
        if PortfolioLedgerEntry.where(portfolio_id: pid).exists?
          return PortfolioLedgerEntry.where(portfolio_id: pid).sum(:realized_pnl_delta).to_f.round(2)
        end

        port = Portfolio.find(pid)
        seed = portfolio_session_seed_usd(running_session).to_d
        delta_balance = port.balance.to_d - seed
        return delta_balance.round(2).to_f if delta_balance.abs >= BigDecimal("0.005")

        Trade.sum_effective_pnl_usd(paper_session_broker_trades_scope(running_session)).round(2)
      end

      def paper_session_broker_trades_scope(running_session)
        pid = running_session.portfolio_id
        broker_settled_trades_scope.where(
          "portfolio_id = ? OR (portfolio_id IS NULL AND closed_at >= ?)",
          pid,
          session_started_at(running_session)
        )
      end

      def dashboard_kpi_trade_totals(running_session, global_totals)
        return global_totals unless paper_session?(running_session)

        Trade.dashboard_pnl_totals_for_scope(paper_session_broker_trades_scope(running_session))
      end

      def paper_session?(running_session)
        Trading::PaperTrading.enabled? && running_session&.portfolio_id.present?
      end

      def session_started_at(session)
        session.started_at || session.created_at || Time.zone.at(0)
      end

      def portfolio_session_seed_usd(session)
        cap = session.capital.to_d
        return cap if cap.positive?

        BigDecimal("20000")
      end

      # Ledger headline (no unrealized): live / no session — wallet math as before. Paper + session —
      # ledger-backed cash when entries exist; else synthetic +seed + realized+ when ledger cash never moved
      # but +Trade+ rows did; else wallet cash / (total − unrealized).
      def dashboard_ledger_equity_usd(wallet:, portfolio:, running_session:, realized_pnl_usd:)
        w = wallet.stringify_keys

        if paper_session?(running_session)
          return paper_headline_equity_usd(
            wallet: w,
            portfolio: portfolio,
            running_session: running_session,
            realized_pnl_usd: realized_pnl_usd
          )
        end

        if w["cash_balance_usd"].present?
          return w["cash_balance_usd"].to_f.round(2)
        end

        if w["total_equity_usd"].present?
          unrealized =
            if w.key?("unrealized_pnl_usd") && !w["unrealized_pnl_usd"].nil?
              w["unrealized_pnl_usd"].to_f
            else
              portfolio.total_pnl.to_f
            end
          return (w["total_equity_usd"].to_f - unrealized).round(2)
        end

        if running_session&.portfolio_id.present?
          return running_session.portfolio.balance.to_f.round(2)
        end

        cfg = Bot::Config.load
        initial_usd = (cfg.simulated_capital_inr.to_f / cfg.usd_to_inr_rate).round(2)
        (initial_usd + realized_pnl_usd).round(2)
      end

      def paper_headline_equity_usd(wallet:, portfolio:, running_session:, realized_pnl_usd:)
        pid = running_session.portfolio_id
        seed = portfolio_session_seed_usd(running_session).to_d
        ledger_active = PortfolioLedgerEntry.where(portfolio_id: pid).exists?

        if ledger_active
          return wallet["cash_balance_usd"].to_f.round(2) if wallet["cash_balance_usd"].present?

          return running_session.portfolio.balance.to_f.round(2)
        end

        # Trade-derived realized moved the session book but wallet cash still shows seed (no ledger rows).
        if realized_pnl_usd.abs >= BigDecimal("0.005")
          return (seed + realized_pnl_usd.to_d).round(2).to_f
        end

        if wallet["cash_balance_usd"].present?
          return wallet["cash_balance_usd"].to_f.round(2)
        end

        if wallet["total_equity_usd"].present?
          unrealized =
            if wallet.key?("unrealized_pnl_usd") && !wallet["unrealized_pnl_usd"].nil?
              wallet["unrealized_pnl_usd"].to_f
            else
              portfolio.total_pnl.to_f
            end
          return (wallet["total_equity_usd"].to_f - unrealized).round(2)
        end

        (seed + realized_pnl_usd.to_d).round(2).to_f
      end

      def dashboard_active_positions(running_session)
        scope = Position.active.order(:symbol)
        if Trading::PaperTrading.enabled? && running_session&.portfolio_id.present?
          scope = scope.where(portfolio_id: running_session.portfolio_id)
        end
        scope.to_a
      end

      def format_trade_calendar_day(value)
        return value.strftime("%Y-%m-%d") if value.respond_to?(:strftime)

        value.to_s
      end

      def load_wallet_for_dashboard(portfolio:, positions:)
        wallet =
          if Trading::PaperTrading.enabled?
            Trading::PaperWalletPublisher.wallet_snapshot!(positions: positions)
          else
            redis_wallet_hash
          end
        wallet.presence || default_wallet_hash(portfolio, positions: positions)
      end

      def equity_curve_from_trades
        curve_dates = (0..6).to_a.reverse.map { |days_ago| days_ago.days.ago.in_time_zone.to_date }
        by_date = Hash.new(0.0)
        Trade.where.not(closed_at: nil).where("closed_at::date IN (?)", curve_dates).find_each do |t|
          by_date[t.closed_at.in_time_zone.to_date] += t.effective_pnl_usd.to_f
        end
        curve_dates.map { |date| by_date[date].round(2) }
      end

      def redis_wallet_hash
        raw = Redis.new.get("delta:wallet:state")
        return nil if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      def default_wallet_hash(portfolio, positions: nil)
        equity_usd = 1000.0 + portfolio.total_pnl.to_f
        base = {
          "balance" => 1000.0,
          "equity" => equity_usd
        }
        return base unless Trading::PaperTrading.enabled?

        cfg = Bot::Config.load
        unreal = portfolio.total_pnl.to_f
        cash = (equity_usd - unreal).round(2)
        base.merge(
          "cash_balance_usd" => cash,
          "cash_balance_inr" => (cash * cfg.usd_to_inr_rate).round(0),
          "unrealized_pnl_usd" => unreal.round(2),
          "unrealized_pnl_inr" => (unreal * cfg.usd_to_inr_rate).round(0),
          "total_equity_usd" => equity_usd.round(2),
          "total_equity_inr" => (equity_usd * cfg.usd_to_inr_rate).round(0),
          "available_usd" => cash,
          "available_inr" => (cash * cfg.usd_to_inr_rate).round(0),
          "blocked_margin_usd" => 0.0,
          "blocked_margin_inr" => 0,
          "capital_inr" => cfg.simulated_capital_inr.round(0),
          "paper_mode" => true,
          "updated_at" => Time.current.iso8601,
          "stale" => true
        )
      end

      def calendar_day_string
        raw = @calendar_day_raw.to_s.strip
        return Time.zone.today.strftime("%Y-%m-%d") if raw.blank?

        Date.iso8601(raw).strftime("%Y-%m-%d")
      rescue ArgumentError
        Time.zone.today.strftime("%Y-%m-%d")
      end

      def broker_settled_trades_scope
        Trade.where.not(symbol: [nil, ""])
             .where.not(closed_at: nil)
      end

      def trades_day_value
        raw = @trades_day_raw.to_s.strip
        return Time.zone.today if raw.blank?

        Date.iso8601(raw)
      rescue ArgumentError
        Time.zone.today
      end

      def trades_day_range
        trades_day_value.in_time_zone.all_day
      end

      def normalized_trades_limit
        raw = @trades_limit_raw
        limit =
          case raw
          when nil, "" then BROKER_TRADES_LIMIT_DEFAULT
          else raw.to_i
          end
        limit = BROKER_TRADES_LIMIT_DEFAULT if limit <= 0
        [limit, BROKER_TRADES_LIMIT_MAX].min
      end

      def trade_payload(trade)
        pnl_usd = trade.effective_pnl_usd.to_f
        {
          symbol: trade.symbol,
          side: trade.side,
          size: trade.size&.to_f,
          entry_price: trade.entry_price,
          exit_price: trade.exit_price,
          pnl_usd: pnl_usd,
          pnl_inr: (pnl_usd * USD_INR_FOR_DISPLAY).round(0),
          timestamp: trade.closed_at
        }
      end

      def position_payload(position)
        entry_price = round_price_for_json(position.entry_price)
        mark = round_price_for_json(Rails.cache.read("ltp:#{position.symbol}")) || entry_price
        unrealized_usd = unrealized_pnl_usd(position: position, mark: mark).round(2)
        opened_at = position.entry_time || position.created_at

        {
          symbol: position.symbol,
          side: position.side,
          size: position.size,
          entry_price: entry_price,
          mark_price: mark,
          opened_at: opened_at&.iso8601,
          unrealized_pnl: unrealized_usd,
          unrealized_pnl_inr: (unrealized_usd * USD_INR_FOR_DISPLAY).round(0),
          unrealized_pnl_pct: unrealized_pnl_pct(position, unrealized_usd),
          leverage: position.leverage,
          status: position.status
        }
      end

      def unrealized_pnl_pct(position, unrealized_usd)
        return 0.0 if unrealized_usd.zero?

        denominator = initial_margin_usd(position)
        return 0.0 if denominator.abs < 1e-12

        ((unrealized_usd / denominator) * 100).round(2)
      end

      def initial_margin_usd(position)
        lev = position.leverage.to_f
        return 0.0 if lev <= 0

        lots = position.size.to_f
        entry = position.entry_price.to_f
        return 0.0 if lots <= 0 || entry <= 0

        lot = Trading::Risk::PositionLotSize.multiplier_for(position).to_f
        (lots * lot * entry) / lev
      end

      def round_price_for_json(value)
        d = value&.to_d
        return nil if d.nil?

        d.round(8).to_f
      end

      def unrealized_pnl_usd(position:, mark:)
        m = mark
        m = position.entry_price if m.nil? || m.to_f.zero?
        Trading::Risk::PositionRisk.call(position: position, mark_price: m).unrealized_pnl.to_f
      end

      def build_market_rows
        SymbolConfig.where(enabled: true).map do |config|
          {
            symbol: config.symbol,
            price: Rails.cache.read("ltp:#{config.symbol}")&.to_f || 0.0,
            leverage: config.leverage
          }
        end
      end

      def build_signal_activity
        {
          last_signal: signal_activity_payload(GeneratedSignal.order(created_at: :desc).first),
          last_rejection: signal_activity_payload(
            GeneratedSignal.where(status: %w[rejected failed]).order(created_at: :desc).first
          )
        }
      end

      def resolve_running_session
        TradingSession.where(status: "running")
                      .order(Arel.sql("COALESCE(started_at, created_at) DESC NULLS LAST"), id: :desc)
                      .first
      end

      # Cross-session: restarting the runner creates a new TradingSession; filtering only the
      # current session made the operational timeline look empty while the bot was still trading.
      def build_recent_signals(limit:)
        GeneratedSignal.order(created_at: :desc).limit(limit).map { |r| signal_activity_payload(r) }
      end

      def signal_activity_payload(record)
        return nil unless record

        {
          id: record.id,
          trading_session_id: record.trading_session_id,
          symbol: record.symbol,
          side: record.side,
          status: record.status,
          strategy: record.strategy,
          source: record.source,
          entry_price: record.entry_price.to_f,
          candle_timestamp: record.candle_timestamp,
          error_message: record.error_message,
          created_at: record.created_at.iso8601(3)
        }
      end

      def build_execution_health
        latest = Bot::Execution::IncidentStore.latest
        return { healthy: true, last_order_error: nil, last_broker_error_code: nil, category: nil, recent_incidents: [] } if latest.nil?

        {
          healthy: false,
          category: latest["category"],
          last_order_error: latest["message"],
          last_broker_error_code: latest.dig("details", "broker_code"),
          recent_incidents: Bot::Execution::IncidentStore.recent(limit: 10)
        }
      end
    end
  end
end
