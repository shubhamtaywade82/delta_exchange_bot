# frozen_string_literal: true

module Trading
  # ReconciliationJob recomputes dirty positions from persisted fills to heal WS drift.
  class ReconciliationJob < ApplicationJob
    queue_as :critical
    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5
    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 5
    retry_on ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    # Recomputes dirty positions only.
    # @return [void]
    def perform
      Position.where(needs_reconciliation: true).find_each do |position|
        Trading::PositionRecalculator.call(position.id)
      end
    end
  end
end
