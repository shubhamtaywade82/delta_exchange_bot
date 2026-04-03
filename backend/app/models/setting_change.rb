# frozen_string_literal: true

class SettingChange < ApplicationRecord
  belongs_to :setting

  validates :key, presence: true
  validates :new_value, presence: true
  validates :new_value_type, presence: true
  validates :source, presence: true
end
