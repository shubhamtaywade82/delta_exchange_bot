# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuntimeSettingUi do
  describe ".payload_for" do
    it "returns toggle for boolean value_type" do
      expect(described_class.payload_for("any.key", value_type: "boolean")).to eq("widget" => "toggle")
    end

    it "returns select for bot.mode" do
      ui = described_class.payload_for("bot.mode", value_type: "string")
      expect(ui["widget"]).to eq("select")
      expect(ui["options"].map { |o| o["value"] }).to eq(%w[dry_run testnet live])
    end

    it "returns number with bounds for risk.max_concurrent_positions" do
      ui = described_class.payload_for("risk.max_concurrent_positions", value_type: "integer")
      expect(ui["widget"]).to eq("number")
      expect(ui["min"]).to eq(1)
      expect(ui["max"]).to eq(20)
    end

    it "returns password widget for api_key keys" do
      expect(described_class.payload_for("ai.ollama_api_key", value_type: "string")["widget"]).to eq("password")
    end
  end
end
