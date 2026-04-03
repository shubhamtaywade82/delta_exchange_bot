# frozen_string_literal: true

module Delta
  class PaperProductsSyncJob < ApplicationJob
    queue_as :market_data

    def perform(symbols = nil)
      list = symbols.presence
      list = Array(list).map(&:to_s).presence
      Delta::PaperCatalog.sync_products!(symbols: list)
    rescue StandardError => e
      Rails.logger.error("[Delta::PaperProductsSyncJob] #{e.class}: #{e.message}")
      raise
    end
  end
end
