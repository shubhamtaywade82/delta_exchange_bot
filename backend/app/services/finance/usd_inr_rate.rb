# frozen_string_literal: true

module Finance
  # USD/INR for sizing, trade pnl_inr, and INR display — same value as +Bot::Config.load.usd_to_inr_rate+
  # (defaults → config/bot.yml → +Setting+ +risk.usd_to_inr_rate+, etc.).
  module UsdInrRate
    FALLBACK = 85.0

    def self.current
      Bot::Config.load.usd_to_inr_rate
    rescue Bot::Config::ValidationError, StandardError
      FALLBACK
    end
  end
end
