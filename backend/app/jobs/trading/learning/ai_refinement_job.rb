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
        payload = JSON.parse(response)
        apply_strategy_bounds(payload["strategies"] || payload)
        apply_runtime_settings(payload["runtime"] || {})
      rescue StandardError => e
        Rails.logger.warn("[AiRefinementJob] skipped: #{e.class} #{e.message}")
      end

      private

      def build_summary
        rows = Trade.order(updated_at: :desc)
                    .limit(500)
                    .pluck(:strategy, :regime, :realized_pnl, :fees, :features, :holding_time_ms)

        grouped_rewards = rows.group_by { |strategy, regime, *_rest| [strategy, regime] }
                              .transform_values do |trades|
          rewards = trades.map { |trade_data| reward_from_row(trade_data).to_f }
          { count: trades.size, mean_reward: rewards.sum / [rewards.size, 1].max }
        end

        grouped_rewards
      end

      def reward_from_row(trade_data)
        _strategy, _regime, realized_pnl, fees, features, holding_time_ms = trade_data
        gross = realized_pnl.to_d
        trade_fees = fees.to_d
        gst = trade_fees * Trading::Learning::Reward::GST_RATE
        net = gross - trade_fees - gst

        notional = features.fetch("notional", 0).to_d
        return 0.to_d if notional.zero?

        reward = net / notional
        time_penalty = holding_time_ms.to_d / 60_000.to_d
        reward - (0.0001.to_d * time_penalty)
      end

      def prompt(summary)
        <<~PROMPT
          Optimize parameter bounds and runtime risk controls for online strategy learning.
          Summary: #{summary.to_json}
          Output JSON ONLY with this schema:
          {
            "strategies": {
              "scalping": {"aggression_min":0.3,"aggression_max":0.9,"risk_min":0.8,"risk_max":1.2}
            },
            "runtime": {
              "learning.epsilon": 0.04,
              "risk.max_margin_utilization": 0.38,
              "risk.daily_loss_cap_pct": 0.045
            }
          }
        PROMPT
      end

      def apply_strategy_bounds(bounds)
        return unless bounds.is_a?(Hash)

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

      def apply_runtime_settings(runtime)
        return unless runtime.is_a?(Hash)

        apply_bounded_runtime_float("learning.epsilon", runtime["learning.epsilon"], min: 0.0, max: 0.5)
        apply_bounded_runtime_float("risk.max_margin_utilization", runtime["risk.max_margin_utilization"], min: 0.1, max: 0.95)
        apply_bounded_runtime_float("risk.daily_loss_cap_pct", runtime["risk.daily_loss_cap_pct"], min: 0.01, max: 0.3)
      end

      def apply_bounded_runtime_float(key, raw_value, min:, max:)
        return if raw_value.nil?

        value = Float(raw_value)
        bounded = [[value, max].min, min].max
        Setting.apply!(
          key: key,
          value: bounded,
          value_type: "float",
          source: "ai_refinement_job",
          reason: "auto_calibration",
          metadata: { job: self.class.name }
        )
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
