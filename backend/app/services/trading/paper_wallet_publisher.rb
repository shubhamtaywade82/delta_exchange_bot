# frozen_string_literal: true

module Trading
  # Pushes blocked margin + unrealized PnL into Redis for the wallet API when running unified paper mode.
  class PaperWalletPublisher
    # Recomputes from DB (active positions) + trades, refreshes Redis, returns payload for API consumers.
    # Call this when reads must not show stale blocked margin (e.g. dashboard) — not only on fills.
    def self.wallet_snapshot!
      return nil unless PaperTrading.enabled?

      cfg = Bot::Config.load
      manager = Bot::Account::CapitalManager.new(
        usd_to_inr_rate: cfg.usd_to_inr_rate,
        dry_run: true,
        simulated_capital_inr: cfg.simulated_capital_inr
      )
      blocked = Position.active.sum(:margin).to_f
      unrealized = unrealized_pnl_usd
      manager.persist_state(blocked_margin: blocked, unrealized_pnl: unrealized)
    end

    def self.publish!
      wallet_snapshot!
    end

    def self.unrealized_pnl_usd
      Position.active.sum do |position|
        mark = Rails.cache.read("ltp:#{position.symbol}")&.to_d || position.entry_price.to_d
        Risk::PositionRisk.call(position: position, mark_price: mark).unrealized_pnl.to_f
      end
    end
  end
end
