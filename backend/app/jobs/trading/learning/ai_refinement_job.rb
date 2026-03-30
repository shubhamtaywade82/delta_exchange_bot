# frozen_string_literal: true

require "json"

module Trading
  module Learning
    # AiRefinementJob periodically asks Ollama for parameter bounds from trade summaries.
    class AiRefinementJob < ApplicationJob
      queue_as :low

      # @return [void]
      def perform
        summary = build_summary
        response = Ai::OllamaClient.ask(prompt(summary))
        bounds = JSON.parse(response)
        apply_bounds(bounds)
      rescue StandardError => e
        Rails.logger.warn("[AiRefinementJob] skipped: #{e.class} #{e.message}")
      end

      private

      def build_summary
        Trade.order(updated_at: :desc)
             .limit(500)
             .group_by { |t| [t.strategy, t.regime] }
             .transform_values do |trades|
          rewards = trades.map { |trade| Trading::Learning::Reward.call(trade).to_f }
          { count: trades.size, mean_reward: rewards.sum / [rewards.size, 1].max }
        end
      end

      def prompt(summary)
        <<~PROMPT
          Optimize parameter bounds for online strategy learning.
          Summary: #{summary.to_json}
          Output JSON ONLY:
          {
            "scalping": {"aggression_min":0.3,"aggression_max":0.9,"risk_min":0.8,"risk_max":1.2}
          }
        PROMPT
      end

      def apply_bounds(bounds)
        bounds.each do |strategy, b|
          min_aggr = b.fetch("aggression_min", 0.1).to_d
          max_aggr = b.fetch("aggression_max", 2.0).to_d
          min_risk = b.fetch("risk_min", 0.1).to_d
          max_risk = b.fetch("risk_max", 2.0).to_d

          StrategyParam.where(strategy: strategy).find_each do |param|
            param.update!(
              aggression: [[param.aggression.to_d, max_aggr].min, min_aggr].max,
              risk_multiplier: [[param.risk_multiplier.to_d, max_risk].min, min_risk].max
            )
          end
        end
      end
    end
  end
end
