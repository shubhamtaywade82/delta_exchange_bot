require "rails_helper"

RSpec.describe "Api::Settings", type: :request do
  it "lists persisted settings" do
    Setting.create!(key: "risk.max_concurrent_positions", value: "7", value_type: "integer")

    get "/api/settings"

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload).to be_an(Array)
    expect(payload.first["key"]).to eq("risk.max_concurrent_positions")
    expect(payload.first["typed_value"]).to eq(7)
    expect(payload.first["ui"]).to be_a(Hash)
    expect(payload.first["ui"]["widget"]).to eq("number")
  end

  it "updates setting and refreshes runtime cache" do
    Setting.create!(key: "learning.epsilon", value: "0.05", value_type: "float")
    allow(Trading::RuntimeConfig).to receive(:refresh!).and_call_original
    allow(Trading::Learning::AiRefinementTrigger).to receive(:call)

    patch "/api/settings/learning.epsilon", params: { key: "learning.epsilon", value: "0.15", value_type: "float" }

    expect(response).to have_http_status(:ok)
    expect(Trading::RuntimeConfig).to have_received(:refresh!).with("learning.epsilon")
    expect(Setting.find_by(key: "learning.epsilon")&.value).to eq("0.15")
    change = SettingChange.order(:created_at).last
    expect(change.key).to eq("learning.epsilon")
    expect(change.source).to eq("api")
    expect(change.reason).to eq("manual_update")
    expect(Trading::Learning::AiRefinementTrigger)
      .to have_received(:call).with(reason: "setting_change:learning.epsilon")
  end

  it "lists recent setting changes" do
    setting = Setting.create!(key: "risk.max_margin_utilization", value: "0.40", value_type: "float")
    setting.setting_changes.create!(
      key: setting.key,
      old_value: "0.35",
      new_value: "0.40",
      old_value_type: "float",
      new_value_type: "float",
      source: "api",
      reason: "manual_update",
      metadata: {}
    )

    get "/api/settings/changes", params: { limit: 10 }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload).to be_an(Array)
    expect(payload.first["key"]).to eq("risk.max_margin_utilization")
    expect(payload.first["new_value"]).to eq("0.40")
  end
end
