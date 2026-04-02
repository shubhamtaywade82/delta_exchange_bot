# frozen_string_literal: true

module Bot
  module Execution
    class RiskCalculator
      def initialize(usd_to_inr_rate:)
        @usd_to_inr_rate = usd_to_inr_rate
      end

      # Returns final contract count as Integer (0 means skip trade).
      def compute(available_usdt:, entry_price_usd:, leverage:, risk_per_trade_pct:,
                  trail_pct:, contract_value:, max_margin_per_position_pct:, side: "buy")
        trail_distance = entry_price_usd * (trail_pct / 100.0)
        stop_price = stop_for_side(entry_price_usd, trail_distance, side)
        margin_wallet_usd = available_usdt * (max_margin_per_position_pct / 100.0)

        result = Finance::PositionSizer.compute!(
          balance_inr: available_usdt * @usd_to_inr_rate,
          risk_percent: risk_per_trade_pct / 100.0,
          entry_price: entry_price_usd,
          stop_price: stop_price,
          contract_value: contract_value,
          usd_inr: @usd_to_inr_rate,
          leverage: leverage,
          margin_wallet_usd: margin_wallet_usd
        )

        result.final_contracts
      end

      private

      def stop_for_side(entry, trail_distance, side)
        case side.to_s.downcase
        when "sell", "short"
          entry + trail_distance
        else
          entry - trail_distance
        end
      end
    end
  end
end
