# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setting, type: :model do
  describe ".apply!" do
    before do
      allow(Trading::Learning::AiRefinementTrigger).to receive(:call)
    end

    it "rolls back the setting write when the audit row cannot be created" do
      described_class.create!(key: "txn.rollback", value: "original", value_type: "string")

      invalid = SettingChange.new.tap { |c| c.errors.add(:base, "simulated failure") }
      allow_any_instance_of(SettingChange).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

      expect do
        described_class.apply!(key: "txn.rollback", value: "updated", value_type: "string", source: "spec")
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(described_class.find_by(key: "txn.rollback").value).to eq("original")
    end

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

    it "triggers event-driven refinement when value changes" do
      described_class.apply!(key: "learning.epsilon", value: 0.08, value_type: "float", source: "spec")

      expect(Trading::Learning::AiRefinementTrigger)
        .to have_received(:call).with(reason: "setting_change:learning.epsilon").once
    end

    it "does not re-trigger refinement for AI-originated write" do
      described_class.apply!(key: "learning.epsilon", value: 0.08, value_type: "float", source: "ai_refinement_job")

      expect(Trading::Learning::AiRefinementTrigger).not_to have_received(:call)
    end
  end
end
