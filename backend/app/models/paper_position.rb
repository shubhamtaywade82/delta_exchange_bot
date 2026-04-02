# frozen_string_literal: true

class PaperPosition < ApplicationRecord
  belongs_to :paper_wallet
  belongs_to :paper_product_snapshot

  validates :side, inclusion: { in: %w[buy sell] }
  validates :net_quantity, numericality: { only_integer: true }
  validates :avg_entry_price, :risk_unit_per_contract, presence: true

  def unrealized_pnl(ltp)
    ltp = ltp.to_d
    qty = net_quantity.to_d
    unit = risk_unit_per_contract.to_d
    entry = avg_entry_price.to_d

    case side
    when "buy"
      (ltp - entry) * qty * unit
    when "sell"
      (entry - ltp) * qty * unit
    else
      0.to_d
    end
  end

  def closing_side
    side == "buy" ? "sell" : "buy"
  end
end
