# frozen_string_literal: true

module Finance
  # Single source for the app Setting used by sizing and display (see also bot.yml risk.usd_to_inr_rate).
  module UsdInrRate
    SETTING_KEY = "usd_to_inr_rate"

    def self.current
      Setting.find_by(key: SETTING_KEY)&.value&.to_f&.nonzero? || 85.0
    end
  end
end
