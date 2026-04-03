# frozen_string_literal: true

class ConsolidateUsdInrSettingKey < ActiveRecord::Migration[8.1]
  LEGACY_KEY = "usd_to_inr_rate"
  CANONICAL_KEY = "risk.usd_to_inr_rate"

  def up
    legacy = Setting.find_by(key: LEGACY_KEY)
    return if legacy.nil?

    if Setting.find_by(key: CANONICAL_KEY).nil?
      Setting.create!(
        key: CANONICAL_KEY,
        value: legacy.value,
        value_type: legacy.value_type.presence || "float"
      )
    end

    legacy.destroy!
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
