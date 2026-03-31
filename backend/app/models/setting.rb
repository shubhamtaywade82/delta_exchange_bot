class Setting < ApplicationRecord
  VALUE_TYPES = %w[string integer float boolean].freeze

  validates :key, presence: true, uniqueness: true
  validates :value_type, inclusion: { in: VALUE_TYPES }, allow_nil: true

  def typed_value
    case (value_type || "string")
    when "integer" then value.to_i
    when "float" then value.to_f
    when "boolean" then boolean_value?
    else value
    end
  end

  private

  def boolean_value?
    value.to_s.strip.downcase.in?(%w[1 true yes on])
  end
end
