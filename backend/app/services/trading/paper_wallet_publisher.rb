# frozen_string_literal: true

module Trading
  # Pushes blocked margin + unrealized PnL into Redis for the wallet API when running unified paper mode.
  class PaperWalletPublisher
    # Recomputes from DB (active positions) + trades, refreshes Redis, returns payload for API consumers.
    # Call this when reads must not show stale blocked margin (e.g. dashboard) — not only on fills.
    # Pass +positions+ when callers already loaded active rows to avoid duplicate queries.
    def self.wallet_snapshot!(positions: nil)
      return nil unless PaperTrading.enabled?

      cfg = Bot::Config.load
      manager = Bot::Account::CapitalManager.new(
        usd_to_inr_rate: cfg.usd_to_inr_rate,
        dry_run: true,
        simulated_capital_inr: cfg.simulated_capital_inr
      )
      rows = positions.nil? ? Position.active.to_a : positions.to_a
      blocked = rows.sum { |position| position.margin.to_f }
      unrealized = unrealized_pnl_usd_for(rows)
      manager.persist_state(blocked_margin: blocked, unrealized_pnl: unrealized)
    end

    def self.publish!(positions: nil)
      wallet_snapshot!(positions: positions)
    end

    def self.unrealized_pnl_usd
      unrealized_pnl_usd_for(Position.active.to_a)
    end

    def self.unrealized_pnl_usd_for(positions)
      positions.sum do |position|
        mark = Rails.cache.read("ltp:#{position.symbol}")&.to_d || position.entry_price.to_d
        Risk::PositionRisk.call(position: position, mark_price: mark).unrealized_pnl.to_f
      end
    end
  end
end
