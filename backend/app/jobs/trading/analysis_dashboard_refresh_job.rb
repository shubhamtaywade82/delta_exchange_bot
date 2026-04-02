# frozen_string_literal: true

module Trading
  # Refreshes Redis-backed SMC / structure digests for all enabled symbols (REST candles).
  class AnalysisDashboardRefreshJob < ApplicationJob
    queue_as :low

    STAGGER_S = Float(ENV.fetch("ANALYSIS_SYMBOL_STAGGER_S", "0.5"))

    def perform
      config = Bot::Config.load
      client = RunnerClient.build
      market_data = client.market_data
      symbols = SymbolConfig.where(enabled: true).order(:symbol).pluck(:symbol)
      rows = []

      symbols.each_with_index do |sym, index|
        sleep(STAGGER_S) if index.positive?
        rows << Trading::Analysis::DigestBuilder.call(
          symbol: sym,
          market_data: market_data,
          config: config
        )
      rescue StandardError => e
        Rails.logger.error("[AnalysisDashboardRefreshJob] #{sym}: #{e.class}: #{e.message}")
        rows << {
          symbol: sym,
          error: e.message,
          updated_at: Time.current.iso8601
        }
      end

      Trading::Analysis::Store.write(
        "updated_at" => Time.current.iso8601,
        "symbols" => rows,
        "meta" => {
          "source" => "AnalysisDashboardRefreshJob",
          "symbol_count" => symbols.size
        }
      )
    end
  end
end
