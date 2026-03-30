# frozen_string_literal: true

module Trading
  module Learning
    # Reward computes normalized net reward from realized PnL, fees, GST and holding time.
    class Reward
      GST_RATE = 0.18.to_d

      # @param trade [Trade]
      # @return [BigDecimal]
      def self.call(trade)
        gross = trade.realized_pnl.to_d
        fees = trade.fees.to_d
        gst = fees * GST_RATE
        net = gross - fees - gst

        notional = trade.features.fetch("notional", 0).to_d
        return 0.to_d if notional.zero?

        reward = net / notional
        time_penalty = trade.holding_time_ms.to_d / 60_000.to_d

        reward - (0.0001.to_d * time_penalty)
      end
    end
  end
end
