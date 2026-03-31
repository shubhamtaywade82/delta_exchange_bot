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
  end

  it "updates setting and refreshes runtime cache" do
    Setting.create!(key: "learning.epsilon", value: "0.05", value_type: "float")
    allow(Trading::RuntimeConfig).to receive(:refresh!).and_call_original

    patch "/api/settings/learning.epsilon", params: { key: "learning.epsilon", value: "0.15", value_type: "float" }

    expect(response).to have_http_status(:ok)
    expect(Trading::RuntimeConfig).to have_received(:refresh!).with("learning.epsilon")
    expect(Setting.find_by(key: "learning.epsilon")&.value).to eq("0.15")
    change = SettingChange.order(:created_at).last
    expect(change.key).to eq("learning.epsilon")
    expect(change.source).to eq("api")
    expect(change.reason).to eq("manual_update")
  end
end
