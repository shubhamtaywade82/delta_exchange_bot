# frozen_string_literal: true

module Trading
  # Syncs Delta product + ticker fields into SymbolConfig (Solid Queue / ActiveJob).
  class PersistProductSnapshotsJob < ApplicationJob
    queue_as :low

    def perform(symbols = nil)
      list = symbols.presence
      list = Array(list).map(&:to_s).presence
      Trading::Delta::ProductCatalogSync.sync_all!(symbols: list)
    end
  end
end
