# frozen_string_literal: true

module Trading
  # ReconciliationJob recomputes dirty positions from persisted fills to heal WS drift.
  class ReconciliationJob < ApplicationJob
    queue_as :critical
    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5
    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 5
    retry_on ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    # Recomputes positions from fills. Default: rows with needs_reconciliation.
    # Set POSITION_RECONCILE_ALL_ACTIVE=true to recalc every active position (full heal).
    # @return [void]
    def perform
      if truthy_env?("POSITION_RECONCILE_ALL_ACTIVE")
        Trading::PositionReconciliation.recalculate_all_active!
        return
      end

      Position.where(needs_reconciliation: true).find_each do |position|
        Trading::PositionRecalculator.call(position.id)
      end
    end

    private

    def truthy_env?(key)
      ActiveModel::Type::Boolean.new.cast(ENV[key])
    end
  end
end
