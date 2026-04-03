# frozen_string_literal: true

module Trading
  module Risk
    # Portfolio-level PnL and exposure limits that block new entries or halt trading.
    # For cancel-all / flatten-session behavior, use Trading::EmergencyShutdown.
    class PortfolioGuard
      MAX_DAILY_LOSS = ENV.fetch("RISK_MAX_DAILY_LOSS", "-10000").to_d
      MAX_EXPOSURE = ENV.fetch("RISK_MAX_EXPOSURE", "100000").to_d

      # @param portfolio [Trading::Risk::PortfolioSnapshot::Result]
      # @return [Symbol] :ok, :block_new_trades, :halt_trading
      def self.call(portfolio:)
        return :halt_trading if portfolio.total_pnl <= MAX_DAILY_LOSS
        return :block_new_trades if portfolio.total_exposure >= MAX_EXPOSURE

        :ok
      end
    end
  end
end
