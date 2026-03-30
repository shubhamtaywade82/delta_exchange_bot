# frozen_string_literal: true

module Trading
  # StrategyRetrainJob summarizes trade outcomes for offline AI prompt adaptation.
  class StrategyRetrainJob < ApplicationJob
    queue_as :critical

    # @return [void]
    def perform
      summary = Trade.group(:regime, :strategy)
                     .select("regime, strategy, AVG(realized_edge) AS avg_realized_edge, COUNT(*) AS trades_count")
                     .map { |row| { regime: row.regime, strategy: row.strategy, avg_realized_edge: row.avg_realized_edge, trades_count: row.trades_count } }

      Rails.cache.write("adaptive:training_summary", summary, expires_in: 1.hour)
      Rails.logger.info("[StrategyRetrainJob] summary=#{summary.to_json}")
    end
  end
end
