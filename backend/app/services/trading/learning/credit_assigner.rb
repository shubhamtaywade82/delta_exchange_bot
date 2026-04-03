# frozen_string_literal: true

module Trading
  module Learning
    # CreditAssigner writes fill-aware trade outcomes for online learner updates.
    class CreditAssigner
      # @param position [Position]
      # @param entry_features [Hash]
      # @param strategy [String]
      # @param regime [String]
      # @return [Trade]
      def self.finalize_trade!(position, entry_features:, strategy:, regime:)
        notional = position.size.to_d.abs * position.entry_price.to_d
        realized_pnl = position.pnl_usd.to_d
        fees = position.fee_total.to_d
        entry_t = position.entry_time || position.created_at
        duration_sec = entry_t.present? ? (Time.current - entry_t.to_time).to_i : 0

        Trade.create!(
          portfolio_id: position.portfolio_id,
          symbol: position.symbol,
          side: position.side,
          size: position.size,
          entry_price: position.entry_price,
          exit_price: position.exit_price,
          pnl_usd: realized_pnl,
          pnl_inr: position.pnl_inr.to_d,
          closed_at: Time.current,
          duration_seconds: duration_sec,
          strategy: strategy,
          regime: regime,
          expected_edge: entry_features["expected_edge"].to_d,
          realized_pnl: realized_pnl,
          realized_edge: realized_edge(realized_pnl: realized_pnl, fees: fees, notional: notional),
          fees: fees,
          holding_time_ms: holding_time_ms(position),
          features: entry_features.merge("notional" => notional)
        )
      end

      def self.holding_time_ms(position)
        return 0 unless position.entry_time.present?

        ((Time.current - position.entry_time) * 1000).to_i
      end

      def self.realized_edge(realized_pnl:, fees:, notional:)
        return 0.to_d if notional <= 0

        ((realized_pnl - fees) / notional).to_d
      end
    end
  end
end
