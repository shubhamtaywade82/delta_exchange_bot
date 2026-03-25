# frozen_string_literal: true

module Bot
  module Execution
    class RiskCalculator
      def initialize(usd_to_inr_rate:)
        @usd_to_inr_rate = usd_to_inr_rate
      end

      # Returns final_lots as Integer (0 means skip trade)
      def compute(available_usdt:, entry_price_usd:, leverage:, risk_per_trade_pct:,
                  trail_pct:, contract_value:, max_margin_per_position_pct:)
        capital_inr    = available_usdt * @usd_to_inr_rate
        risk_inr       = capital_inr * (risk_per_trade_pct / 100.0)
        risk_usd       = risk_inr / @usd_to_inr_rate

        trail_distance = entry_price_usd * (trail_pct / 100.0)
        loss_per_lot   = trail_distance * contract_value

        return 0 if loss_per_lot.zero?

        raw_lots       = risk_usd / loss_per_lot
        leveraged_lots = raw_lots * leverage
        final_lots     = leveraged_lots.floor

        return 0 if final_lots <= 0

        # Margin cap: (lots × contract_value × price) / leverage <= available × cap%
        max_margin_usd  = available_usdt * (max_margin_per_position_pct / 100.0)
        margin_per_lot  = (contract_value * entry_price_usd) / leverage

        if margin_per_lot.positive?
          max_lots_by_margin = (max_margin_usd / margin_per_lot).floor
          final_lots = [final_lots, max_lots_by_margin].min
        end

        [final_lots, 0].max
      end
    end
  end
end
