# frozen_string_literal: true

module Trading
  # Pushes portfolio wallet + unrealized PnL into Redis for the wallet API when running unified paper mode.
  class PaperWalletPublisher
    # Recomputes from Portfolio (ledger SSOT) when a running session exists; falls back to legacy path.
    def self.wallet_snapshot!(positions: nil)
      return nil unless PaperTrading.enabled?

      cfg = Bot::Config.load
      portfolio = resolve_paper_portfolio
      if portfolio
        persist_portfolio_payload(cfg, portfolio)
      else
        legacy_snapshot!(cfg, positions)
      end
    end

    def self.publish!(positions: nil)
      wallet_snapshot!(positions: positions)
    end

    def self.unrealized_pnl_usd
      portfolio = resolve_paper_portfolio
      return portfolio.unrealized_pnl_total.to_f if portfolio

      unrealized_pnl_usd_for(Position.active.to_a)
    end

    def self.unrealized_pnl_usd_for(positions)
      positions.sum do |position|
        mark = MarkPrice.for_symbol(position.symbol)&.to_d || position.entry_price.to_d
        Risk::PositionRisk.call(position: position, mark_price: mark).unrealized_pnl.to_f
      end
    end

    def self.resolve_paper_portfolio
      pid = TradingSession.where(status: "running").limit(1).pick(:portfolio_id)
      Portfolio.find_by(id: pid) if pid
    end

    def self.persist_portfolio_payload(cfg, portfolio)
      # +used_margin+ can drift if fills bypass the normal path; recompute from open positions before UI.
      portfolio.sync_margin_from_positions!
      blocked = portfolio.used_margin.to_f
      unrealized = portfolio.unrealized_pnl_total.to_f
      balance_usd = portfolio.balance.to_f
      equity_usd = balance_usd + unrealized
      spendable = portfolio.available_balance.to_f
      ledger_margin_exceeds_cash = blocked > balance_usd + 1e-6

      data = {
        "cash_balance_usd" => balance_usd.round(2),
        "cash_balance_inr" => (balance_usd * cfg.usd_to_inr_rate).round(0),
        "unrealized_pnl_usd" => unrealized.round(2),
        "unrealized_pnl_inr" => (unrealized * cfg.usd_to_inr_rate).round(0),
        "total_equity_usd" => equity_usd.round(2),
        "total_equity_inr" => (equity_usd * cfg.usd_to_inr_rate).round(0),
        "available_usd" => spendable.round(2),
        "available_inr" => (spendable * cfg.usd_to_inr_rate).round(0),
        "blocked_margin_usd" => blocked.round(2),
        "blocked_margin_inr" => (blocked * cfg.usd_to_inr_rate).round(0),
        "ledger_margin_exceeds_cash" => ledger_margin_exceeds_cash,
        "capital_inr" => cfg.simulated_capital_inr.round(0),
        "paper_mode" => true,
        "updated_at" => Time.current.iso8601,
        "stale" => false
      }
      Redis.current.set(Bot::Account::CapitalManager::REDIS_KEY, data.to_json)
      data
    rescue StandardError => e
      Rails.logger.warn("[PaperWalletPublisher] Redis persist failed: #{e.message}")
      nil
    end

    def self.legacy_snapshot!(cfg, positions)
      manager = Bot::Account::CapitalManager.new(
        usd_to_inr_rate: cfg.usd_to_inr_rate,
        dry_run: true,
        simulated_capital_inr: cfg.simulated_capital_inr
      )
      rows = positions.nil? ? Position.active.to_a : positions.to_a
      blocked = rows.sum { |position| position.margin.to_f }
      unrealized = unrealized_pnl_usd_for(rows)
      data = manager.persist_state(blocked_margin: blocked, unrealized_pnl: unrealized)
      return data unless data

      equity_usd = data["total_equity_usd"].to_f
      cash_usd = (equity_usd - unrealized).round(2)
      merged = data.merge(
        "cash_balance_usd" => cash_usd,
        "cash_balance_inr" => (cash_usd * cfg.usd_to_inr_rate).round(0),
        "unrealized_pnl_usd" => unrealized.round(2),
        "unrealized_pnl_inr" => (unrealized * cfg.usd_to_inr_rate).round(0)
      )
      Redis.current.set(Bot::Account::CapitalManager::REDIS_KEY, merged.to_json)
      merged
    end
    private_class_method :legacy_snapshot!, :persist_portfolio_payload
  end
end
