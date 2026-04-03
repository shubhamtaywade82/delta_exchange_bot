# frozen_string_literal: true

class Setting < ApplicationRecord
  VALUE_TYPES = %w[string integer float boolean].freeze
  DEFAULT_SOURCE = "unknown"

  validates :key, presence: true, uniqueness: true
  validates :value_type, inclusion: { in: VALUE_TYPES }, allow_nil: true

  has_many :setting_changes, dependent: :delete_all

  def self.apply!(key:, value:, value_type: nil, source: DEFAULT_SOURCE, reason: nil, metadata: {})
    setting = find_or_initialize_by(key: key)
    new_value = value.to_s
    new_type = value_type || infer_value_type(value)
    old_value = setting.value
    old_type = setting.value_type

    return setting if old_value == new_value && old_type == new_type

    setting.value = new_value
    setting.value_type = new_type
    Setting.transaction do
      setting.save!
      setting.setting_changes.create!(
        key: key,
        old_value: old_value,
        new_value: new_value,
        old_value_type: old_type,
        new_value_type: new_type,
        source: source,
        reason: reason,
        metadata: metadata || {}
      )
    end
    Trading::RuntimeConfig.refresh!(key)
    trigger_ai_refinement_for_runtime_change(source: source, key: key)
    setting
  end

  def typed_value
    case (value_type || "string")
    when "integer" then value.to_i
    when "float" then value.to_f
    when "boolean" then boolean_value?
    else value
    end
  end

  private

  def self.infer_value_type(value)
    return "boolean" if value == true || value == false
    return "integer" if value.is_a?(Integer)
    return "float" if value.is_a?(Float) || value.is_a?(BigDecimal)

    str = value.to_s.strip
    return "boolean" if str.downcase.in?(%w[true false 1 0 yes no on off])
    return "integer" if str.match?(/\A-?\d+\z/)
    return "float" if str.match?(/\A-?\d+\.\d+\z/)

    "string"
  end

  def boolean_value?
    value.to_s.strip.downcase.in?(%w[1 true yes on])
  end

  def self.trigger_ai_refinement_for_runtime_change(source:, key:)
    return if source.to_s == "ai_refinement_job"

    Trading::Learning::AiRefinementTrigger.call(reason: "setting_change:#{key}")
  end
  private_class_method :trigger_ai_refinement_for_runtime_change
end
