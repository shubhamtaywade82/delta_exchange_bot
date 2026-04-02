# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::AiSmcSynthesizer do
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
