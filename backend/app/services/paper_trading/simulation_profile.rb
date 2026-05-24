# frozen_string_literal: true

module PaperTrading
  # Centralizes paper execution realism toggles so runner + docs stay aligned.
  module SimulationProfile
    module_function

    # Runner + ExecutionEngine paper fills: when true, uses DeltaLikeFillSimulator (same stack as ProcessSignalJob).
    # Explicit ENV always wins. When unset: production => true (exchange-shaped paper); development/test => false (fast suite).
    def orderbook_simulator_enabled?
      raw = ENV["PAPER_USE_ORDERBOOK_SIMULATOR"].to_s.strip.downcase
      return true if %w[1 true yes on].include?(raw)
      return false if %w[0 false no off].include?(raw)

      Rails.env.production?
    end
  end
end
