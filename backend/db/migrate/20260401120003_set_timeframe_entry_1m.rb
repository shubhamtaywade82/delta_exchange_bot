# frozen_string_literal: true

class SetTimeframeEntry1m < ActiveRecord::Migration[8.1]
  def up
    row = Setting.find_or_initialize_by(key: "strategy.timeframes.entry")
    row.value = "1m"
    row.value_type = "string"
    row.save!
  end

  def down
    Setting.find_by(key: "strategy.timeframes.entry")&.update!(value: "5m")
  end
end
