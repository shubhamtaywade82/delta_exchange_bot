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
    setting = Setting.apply!(
      key: setting_params[:key],
      value: setting_params[:value],
      value_type: setting_params[:value_type].presence || infer_value_type(setting_params[:value]),
      source: "api",
      reason: "manual_update",
      metadata: {
        request_id: request.request_id,
        remote_ip: request.remote_ip
      }
    )
    render json: {
      key: setting.key,
      value: setting.value,
      value_type: setting.value_type,
      typed_value: setting.typed_value
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
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
