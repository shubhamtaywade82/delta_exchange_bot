# frozen_string_literal: true

# Single source of truth: +paper_wallet_ledger_entries+ (+amount_inr+).
# Cached columns on this row (+balance_inr+, +used_margin_inr+, +available_inr+, +realized_pnl_inr+) are derived in +recompute_from_ledger!+.
# Mark-to-market: +unrealized_pnl_inr+ and +equity_inr+ are updated in +refresh_snapshot!+ from open +PaperPosition+ and live prices (USD notionals × FX).
class PaperWallet < ApplicationRecord
  has_many :paper_trading_signals, dependent: :restrict_with_exception
  has_many :paper_orders, dependent: :restrict_with_exception
  has_many :paper_positions, dependent: :destroy
  has_many :paper_wallet_ledger_entries, dependent: :destroy

  validates :name, presence: true
  validates :balance_inr, :available_inr, :used_margin_inr, :equity_inr, :unrealized_pnl_inr, :realized_pnl_inr, presence: true

  def deposit!(amount_inr, meta: {})
    amt = amount_inr.to_d
    raise ArgumentError, "deposit must be positive" unless amt.positive?

    with_lock do
      paper_wallet_ledger_entries.create!(
        entry_type: "deposit",
        direction: "credit",
        amount_inr: amt.round(2),
        meta: meta.stringify_keys,
        reference: nil
      )
      recompute_from_ledger!
    end
    self
  end

  def recompute_from_ledger!
    balance = 0.to_d
    used_margin = 0.to_d
    realized_ledger_inr = 0.to_d

    paper_wallet_ledger_entries.order(:id).each do |e|
      amt = e.amount_inr.to_d
      case e.entry_type
      when "deposit"
        balance += amt if e.direction == "credit"
        balance -= amt if e.direction == "debit"
      when "withdrawal"
        balance -= amt if e.direction == "debit"
        balance += amt if e.direction == "credit"
      when "realized_pnl"
        if e.direction == "credit"
          balance += amt
          realized_ledger_inr += amt
        else
          balance -= amt
          realized_ledger_inr -= amt
        end
      when "commission"
        balance -= amt if e.direction == "debit"
        balance += amt if e.direction == "credit"
      when "margin_reserved"
        used_margin += amt if e.direction == "debit"
        used_margin -= amt if e.direction == "credit"
      when "margin_released"
        used_margin -= amt if e.direction == "credit"
        used_margin += amt if e.direction == "debit"
      end
    end

    used_margin = [ used_margin, 0.to_d ].max
    available = balance - used_margin
    available = 0.to_d if available.negative?

    assign_attributes(
      balance_inr: balance.round(2),
      used_margin_inr: used_margin.round(2),
      available_inr: available.round(2),
      realized_pnl_inr: realized_ledger_inr.round(2),
      equity_inr: (balance.round(2) + unrealized_pnl_inr.to_d).round(2)
    )
    save!
  end

  # ltp_map: { product_id(Integer) => BigDecimal } — marks in USD per contract; converted to INR for display/cache.
  def refresh_snapshot!(ltp_map: {})
    with_lock do
      unrealized_usd = paper_positions.includes(:paper_product_snapshot).reduce(0.to_d) do |sum, pos|
        pid = pos.paper_product_snapshot.product_id
        ltp = ltp_map[pid]&.to_d || pos.paper_product_snapshot.live_price&.to_d
        next sum unless ltp&.positive?

        sum + pos.unrealized_pnl(ltp)
      end

      rate = usd_inr_rate
      unreal_inr = (unrealized_usd * rate).round(2)
      bal = balance_inr.to_d
      used = used_margin_inr.to_d
      avail = (bal - used).round(2)
      avail = 0.to_d if avail.negative?

      assign_attributes(
        unrealized_pnl_inr: unreal_inr,
        available_inr: avail,
        equity_inr: (bal + unreal_inr).round(2)
      )
      save!
    end
  end

  private

  def usd_inr_rate
    Finance::UsdInrRate.current.to_d
  end
end
