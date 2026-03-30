# frozen_string_literal: true

module Trading
  module Learning
    # OnlineUpdater performs bounded incremental parameter updates per strategy+regime.
    class OnlineUpdater
      CLIP = 0.05.to_d

      # @param trade [Trade]
      # @return [StrategyParam, nil]
      def self.update!(trade)
        return nil if freeze_learning?

        reward = Reward.call(trade)
        params = StrategyParam.lock.find_or_create_by!(strategy: trade.strategy, regime: trade.regime)

        alpha = params.alpha.to_d
        delta = alpha * reward
        delta = [[delta, CLIP].min, -CLIP].max

        params.update!(
          bias: params.bias.to_d + delta,
          aggression: bounded(params.aggression.to_d + delta),
          risk_multiplier: bounded(params.risk_multiplier.to_d + delta)
        )

        params
      rescue ActiveRecord::StaleObjectError
        retry
      end

      def self.bounded(value)
        [[value, 2.0.to_d].min, 0.1.to_d].max
      end

      def self.freeze_learning?
        portfolio = Trading::Risk::PortfolioSnapshot.current
        drawdown_limit = ENV.fetch("LEARNING_FREEZE_PNL", "-5000").to_d
        portfolio.total_pnl <= drawdown_limit
      end
    end
  end
end
