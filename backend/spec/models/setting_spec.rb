require "rails_helper"

RSpec.describe Setting, type: :model do
  describe ".apply!" do
    it "persists setting and writes audit row" do
      setting = described_class.apply!(
        key: "learning.epsilon",
        value: 0.09,
        value_type: "float",
        source: "spec",
        reason: "test_update",
        metadata: { ticket: "T-1" }
      )

      expect(setting.value).to eq("0.09")
      expect(setting.value_type).to eq("float")
      change = SettingChange.order(:created_at).last
      expect(change.key).to eq("learning.epsilon")
      expect(change.source).to eq("spec")
      expect(change.reason).to eq("test_update")
      expect(change.metadata).to include("ticket" => "T-1")
    end

    it "does not create audit row when value is unchanged" do
      described_class.apply!(key: "learning.epsilon", value: 0.05, value_type: "float", source: "spec")

      expect do
        described_class.apply!(key: "learning.epsilon", value: 0.05, value_type: "float", source: "spec")
      end.not_to change(SettingChange, :count)
    end
  end
end
