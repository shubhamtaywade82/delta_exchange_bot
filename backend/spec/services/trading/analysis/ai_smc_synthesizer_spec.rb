# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::AiSmcSynthesizer do
  describe ".call" do
    let(:payload) { { "chart" => { "symbol" => "BTCUSD" } } }

    it "returns nil and reports when Ollama raises" do
      allow(Ai::OllamaClient).to receive(:ask).and_raise(StandardError, "model not found")
      allow(Rails.logger).to receive(:warn)
      allow(Rails.error).to receive(:report)

      expect(described_class.call(symbol: "BTCUSD", payload: payload)).to be_nil

      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "model not found"),
        handled: true,
        context: hash_including(
          "component" => "Analysis::AiSmcSynthesizer",
          "symbol" => "BTCUSD",
          "reason" => "error"
        )
      )
    end

    it "returns nil and reports on Ruby Timeout::Error" do
      allow(Ai::OllamaClient).to receive(:ask) { raise Timeout::Error, "execution expired" }
      allow(Rails.logger).to receive(:warn)
      allow(Rails.error).to receive(:report)

      expect(described_class.call(symbol: "ETHUSD", payload: payload)).to be_nil

      expect(Rails.error).to have_received(:report).with(
        instance_of(Timeout::Error),
        handled: true,
        context: hash_including("reason" => "ruby_timeout", "symbol" => "ETHUSD")
      )
    end
  end

  describe ".parse_model_json" do
    it "parses JSON wrapped in a markdown fence" do
      raw = <<~TEXT
        ```json
        {"summary":"ok","htf_bias":"mixed","scenario":"range","confidence_0_to_100":40,"invalidation":"x","takeaway_bullets":["a"],"comment_on_plan":"n","timeframe_notes":{}}
        ```
      TEXT
      out = described_class.parse_model_json(raw)
      expect(out[:summary]).to eq("ok")
      expect(out[:htf_bias]).to eq("mixed")
    end

    it "parses raw JSON with leading noise" do
      raw = 'here: {"summary":"z","htf_bias":"bullish","scenario":"continuation","confidence_0_to_100":80,"invalidation":"","takeaway_bullets":[],"comment_on_plan":"","timeframe_notes":{}}'
      out = described_class.parse_model_json(raw)
      expect(out[:summary]).to eq("z")
    end
  end
end
