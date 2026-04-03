# frozen_string_literal: true

module Delta
  class PaperTickersSyncJob < ApplicationJob
    queue_as :market_data

    def perform(symbols = nil)
      list = symbols.presence
      list = Array(list).map(&:to_s).presence
      Delta::PaperCatalog.sync_tickers!(symbols: list)

      PaperWallet.joins(:paper_positions).distinct.pluck(:id).each do |wid|
        PaperTrading::RepriceWalletJob.perform_later(wid)
      end
    rescue StandardError => e
      Rails.logger.error("[Delta::PaperTickersSyncJob] #{e.class}: #{e.message}")
      raise
    end
  end
end
