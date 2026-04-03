# frozen_string_literal: true

class TuneRunnerDefaults < ActiveRecord::Migration[8.1]
  def up
    interval = Setting.find_by(key: "runner.strategy_interval_seconds")
    if interval&.value == "60"
      interval.update!(value: "30", value_type: "integer")
    end

    return if Setting.exists?(key: "runner.strategy_symbol_stagger_seconds")

    Setting.create!(key: "runner.strategy_symbol_stagger_seconds", value: "1.0", value_type: "float")
  end

  def down
    interval = Setting.find_by(key: "runner.strategy_interval_seconds")
    interval&.update!(value: "60", value_type: "integer") if interval&.value == "30"

    stagger = Setting.find_by(key: "runner.strategy_symbol_stagger_seconds")
    stagger&.destroy if stagger&.value.to_s == "1.0"
  end
end
