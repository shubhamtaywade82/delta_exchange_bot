class Api::SettingsController < ApplicationController
  def index
    settings = Setting.order(:key).map do |setting|
      {
        key: setting.key,
        value: setting.value,
        value_type: setting.value_type || "string",
        typed_value: setting.typed_value
      }
    end
    render json: settings
  end

  def update
    setting = Setting.find_or_initialize_by(key: setting_params[:key])
    setting.value = setting_params[:value].to_s
    setting.value_type = setting_params[:value_type].presence || infer_value_type(setting_params[:value])

    if setting.save
      Trading::RuntimeConfig.refresh!(setting.key)
      render json: {
        key: setting.key,
        value: setting.value,
        value_type: setting.value_type,
        typed_value: setting.typed_value
      }
    else
      render json: { errors: setting.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def setting_params
    return params.require(:setting).permit(:key, :value, :value_type) if params[:setting].present?

    params.permit(:key, :value, :value_type)
  end

  def infer_value_type(value)
    str = value.to_s.strip
    return "boolean" if str.downcase.in?(%w[true false 1 0 yes no on off])
    return "integer" if str.match?(/\A-?\d+\z/)
    return "float" if str.match?(/\A-?\d+\.\d+\z/)

    "string"
  end
end
