# frozen_string_literal: true

module Trading
  # Republishes paper wallet snapshot to Redis for dashboards after ledger changes.
  class RefreshWalletSnapshotJob < ApplicationJob
    queue_as :low

    def perform
      PaperWalletPublisher.publish!
    end
  end
end
