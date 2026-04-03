# frozen_string_literal: true

module Trading
  # Paper / simulation execution: real market data from Delta, no broker order placement.
  # Enabled when EXECUTION_MODE=paper, or (EXECUTION_MODE unset and Bot mode is dry_run), or in development default.
  module PaperTrading
    module_function

    def enabled?
      return false if execution_mode == "live"
      return true if execution_mode == "paper"

      Bot::Config.load.dry_run?
    rescue StandardError
      !Rails.env.production?
    end

    def execution_mode
      ENV["EXECUTION_MODE"].to_s.strip.downcase.presence
    end

    # Private WS channels (orders/fills) mirror the real account — disable in paper to avoid mixing
    # exchange state with simulated positions and to allow running without API keys.
    def subscribe_private_ws_streams?
      !enabled?
    end
  end
end
