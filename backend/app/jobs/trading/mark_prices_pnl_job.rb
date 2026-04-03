# frozen_string_literal: true

module Trading
  # Refreshes stored unrealized PnL from mark/LTP cache and runs liquidation checks.
  class MarkPricesPnlJob < ApplicationJob
    queue_as :low
    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 3

    def perform
      Position.active.find_each do |position|
        mark = MarkPrice.for_symbol(position.symbol)
        next if mark.blank?

        unrealized = Risk::PositionRisk.call(position: position, mark_price: mark).unrealized_pnl
        position.update_column(:unrealized_pnl_usd, unrealized)

        LiquidationEngine.evaluate_and_act!(position, mark_price: mark)
      end
    end
  end
end
