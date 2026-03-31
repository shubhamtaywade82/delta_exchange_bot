# frozen_string_literal: true

module Trading
  # Paper-only: when enabled, RiskManager + KillSwitch gates are skipped so you can test the full pipeline.
  # Stored as Setting `paper.ignore_entry_risk_gates` (boolean). Never applies when `PaperTrading.enabled?` is false.
  module PaperRiskOverride
    KEY = "paper.ignore_entry_risk_gates"

    module_function

    def active?
      return false unless PaperTrading.enabled?

      Setting.find_by(key: KEY)&.typed_value == true
    end

    def set!(enabled:)
      unless PaperTrading.enabled?
        raise ArgumentError, "paper_risk_override requires paper execution mode"
      end

      Setting.apply!(
        key: KEY,
        value: enabled,
        value_type: "boolean",
        source: "dashboard",
        reason: "paper_risk_override_toggle"
      )
      active?
    end
  end
end
