# frozen_string_literal: true

module Trading
  # Pushes portfolio wallet + unrealized PnL into Redis for the wallet API when running unified paper mode.
  class PaperWalletPublisher
    # Recomputes from Portfolio (ledger SSOT) when a running session exists; otherwise uses +PaperWallet+
    # (ledger INR) for +delta:wallet:state+ so the wallet API matches +paper_wallet:deposit+ and fills.
    def self.wallet_snapshot!(positions: nil)
      return nil unless PaperTrading.enabled?

      cfg = Bot::Config.load
      portfolio = resolve_paper_portfolio
      if portfolio
        persist_portfolio_payload(cfg, portfolio)
      elsif (wallet = resolve_dashboard_paper_broker_wallet)
        publish_dashboard_from_paper_wallet!(cfg, wallet)
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

    # Redis +wallet+ API (+delta:wallet:state+) after +PaperWallet+ columns are already fresh (e.g. RepriceWalletJob).
    def self.push_dashboard_redis_after_wallet_refresh!(wallet)
      return unless dashboard_paper_wallet_publishable?
      return unless resolve_dashboard_paper_broker_wallet&.id == wallet.id

      # Avoid +Bot::Config.load+ here (validates watchlist); rate matches +Finance::UsdInrRate+ used on +PaperWallet+.
      write_delta_wallet_state_from_paper_wallet(Finance::UsdInrRate.current, wallet)
    end

    def self.dashboard_paper_wallet_publishable?
      PaperTrading.enabled? && resolve_paper_portfolio.nil?
    end

    def self.resolve_dashboard_paper_broker_wallet
      explicit = ENV["PAPER_UI_WALLET_ID"].presence&.to_i
      return PaperWallet.find_by(id: explicit) if explicit&.positive?

      wallets = PaperWallet.order(:id).limit(2).to_a
      case wallets.size
      when 0 then nil
      when 1 then wallets.first
      else PaperWallet.find_by(id: 1) || wallets.first
      end
    end

    def self.persist_portfolio_payload(cfg, portfolio)
      # +used_margin+ can drift if fills bypass the normal path; recompute from open positions before UI.
      portfolio.sync_margin_from_positions!
      reconcile_position_margins_if_insolvent!(portfolio)
      portfolio.reload.sync_margin_from_positions!

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

    def self.publish_dashboard_from_paper_wallet!(cfg, wallet)
      prepare_paper_wallet_snapshot_columns!(wallet)
      write_delta_wallet_state_from_paper_wallet(cfg.usd_to_inr_rate, wallet.reload)
    end

    def self.prepare_paper_wallet_snapshot_columns!(wallet)
      positions = PaperPosition.where(paper_wallet_id: wallet.id).includes(:paper_product_snapshot).to_a
      product_ids = positions.map { |p| p.paper_product_snapshot.product_id }
      ltp_map = ::PaperTrading::RedisStore.get_all_ltp_for_product_ids(product_ids)
      missing = product_ids.uniq - ltp_map.keys
      PaperProductSnapshot.where(product_id: missing).find_each do |ps|
        px = ps.live_price
        ltp_map[ps.product_id] = px.to_d if px&.to_d&.positive?
      end

      wallet.reload
      wallet.recompute_from_ledger!
      wallet.refresh_snapshot!(ltp_map: ltp_map)
    end

    def self.write_delta_wallet_state_from_paper_wallet(usd_to_inr_rate, wallet)
      rate = usd_to_inr_rate.to_d
      bal = wallet.balance_inr.to_d
      used = wallet.used_margin_inr.to_d
      avail = wallet.available_inr.to_d
      unreal_inr = wallet.unrealized_pnl_inr.to_d
      equity_inr = wallet.equity_inr.to_d
      ledger_margin_exceeds_cash = used > bal + BigDecimal("0.01")

      data = {
        "cash_balance_usd" => (bal / rate).round(2).to_f,
        "cash_balance_inr" => bal.round(0).to_i,
        "unrealized_pnl_usd" => (unreal_inr / rate).round(2).to_f,
        "unrealized_pnl_inr" => unreal_inr.round(0).to_i,
        "total_equity_usd" => (equity_inr / rate).round(2).to_f,
        "total_equity_inr" => equity_inr.round(0).to_i,
        "available_usd" => (avail / rate).round(2).to_f,
        "available_inr" => avail.round(0).to_i,
        "blocked_margin_usd" => (used / rate).round(2).to_f,
        "blocked_margin_inr" => used.round(0).to_i,
        "ledger_margin_exceeds_cash" => ledger_margin_exceeds_cash,
        "capital_inr" => equity_inr.round(0).to_i,
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

    def self.margin_exceeds_ledger_cash?(portfolio)
      portfolio.used_margin.to_d > portfolio.balance.to_d + BigDecimal("1e-6")
    end

    # Sum of +positions.margin+ exceeds ledger +balance+ (often stale leverage or pre-recalc rows). Refresh each
    # open row from fills + session leverage via +PositionRecalculator+, then caller re-syncs portfolio totals.
    def self.reconcile_position_margins_if_insolvent!(portfolio)
      return unless margin_exceeds_ledger_cash?(portfolio)

      Rails.logger.info(
        "[PaperWalletPublisher] Reconciling position margins (blocked > ledger cash) portfolio_id=#{portfolio.id}"
      )
      Position.active_for_portfolio(portfolio.id).find_each do |position|
        Trading::PositionRecalculator.call(position.id)
      rescue StandardError => e
        Rails.logger.warn("[PaperWalletPublisher] PositionRecalculator failed position_id=#{position.id}: #{e.message}")
      end
    end

    private_class_method :legacy_snapshot!, :persist_portfolio_payload, :publish_dashboard_from_paper_wallet!,
                         :prepare_paper_wallet_snapshot_columns!, :write_delta_wallet_state_from_paper_wallet,
                         :margin_exceeds_ledger_cash?, :reconcile_position_margins_if_insolvent!
  end
end
