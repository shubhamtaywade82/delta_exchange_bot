# frozen_string_literal: true

class SetSupertrendVariantMlAdaptive < ActiveRecord::Migration[8.1]
  def up
    row = Setting.find_or_initialize_by(key: "strategy.supertrend.variant")
    row.value = "ml_adaptive"
    row.value_type = "string"
    row.save!
  end

  def down
    Setting.find_by(key: "strategy.supertrend.variant")&.update!(value: "classic")
  end
end
