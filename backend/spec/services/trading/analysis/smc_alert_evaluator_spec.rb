# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::SmcAlertEvaluator do
  describe ".flags_from_confluence" do
    it "derives high-conviction flags from scores and base signals" do
      flags = described_class.flags_from_confluence(
        "long_signal" => true,
        "short_signal" => false,
        "long_score" => 5,
        "short_score" => 2,
        "liq_sweep_bull" => true,
        "liq_sweep_bear" => false,
        "choch_bull" => true,
        "choch_bear" => false,
        "pdh_sweep" => true,
        "pdl_sweep" => false
      )

      expect(flags["long_signal"]).to be(true)
      expect(flags["high_conviction_long"]).to be(true)
      expect(flags["high_conviction_short"]).to be(false)
      expect(flags["liq_sweep_bull"]).to be(true)
      expect(flags["pdh_sweep"]).to be(true)
    end

    it "does not treat score 4 as high conviction long" do
      flags = described_class.flags_from_confluence(
        "long_signal" => true,
        "long_score" => 4
      )
      expect(flags["high_conviction_long"]).to be(false)
    end
  end

  describe ".call" do
    it "no-ops when the feature is disabled via ENV" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANALYSIS_SMC_ALERT_ENABLED").and_return("false")

      expect { described_class.call(symbol: "BTCUSD") }.not_to raise_error
    end
  end

  describe "include_ai_insight?" do
    it "is false when ANALYSIS_SMC_ALERT_INCLUDE_AI is false" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANALYSIS_SMC_ALERT_INCLUDE_AI").and_return("false")

      expect(described_class.send(:include_ai_insight?)).to be(false)
    end
  end
end
