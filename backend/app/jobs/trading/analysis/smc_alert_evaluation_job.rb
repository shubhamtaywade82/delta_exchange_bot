# frozen_string_literal: true

module Trading
  module Analysis
    # Runs SMC confluence evaluation, optional Ollama, and Telegram off the WebSocket tick thread.
    # Enqueued from +SmcAlertEvaluator.call+ after the Redis gate is acquired.
    class SmcAlertEvaluationJob < ApplicationJob
      queue_as :low

      def perform(symbol)
        SmcAlertEvaluator.perform_evaluation!(symbol: symbol)
      end
    end
  end
end
