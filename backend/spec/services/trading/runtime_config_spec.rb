require "rails_helper"

RSpec.describe Trading::RuntimeConfig do
  describe ".fetch_float" do
    it "reads value from Setting with casting" do
      Setting.create!(key: "learning.epsilon", value: "0.12", value_type: "float")

      value = described_class.fetch_float("learning.epsilon", default: 0.05)

      expect(value).to eq(0.12)
    end

    it "falls back to default for invalid value" do
      Setting.create!(key: "learning.epsilon", value: "bad", value_type: "string")

      value = described_class.fetch_float("learning.epsilon", default: 0.05)

      expect(value).to eq(0.05)
    end
  end

  describe ".fetch_boolean" do
    it "returns default and reports when the backing fetch raises" do
      allow(described_class).to receive(:fetch).and_raise(StandardError, "cache/db error")
      allow(Rails.error).to receive(:report)

      value = described_class.fetch_boolean("feature.flag", default: false)

      expect(value).to be(false)
      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "cache/db error"),
        handled: true,
        context: hash_including("component" => "RuntimeConfig", "operation" => "fetch_boolean", "key" => "feature.flag")
      )
    end
  end

  describe ".refresh!" do
    it "evicts cached key and re-reads latest setting" do
      setting = Setting.create!(key: "runner.strategy_interval_seconds", value: "60", value_type: "integer")
      expect(described_class.fetch_integer("runner.strategy_interval_seconds", default: 30)).to eq(60)

      setting.update!(value: "15")
      described_class.refresh!("runner.strategy_interval_seconds")

      expect(described_class.fetch_integer("runner.strategy_interval_seconds", default: 30)).to eq(15)
    end
  end
end
