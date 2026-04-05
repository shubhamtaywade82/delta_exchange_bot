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
    let(:gate_key) { format(described_class::GATE_KEY, symbol: "SMCALRT1") }
    let(:telegram_config) do
      instance_double(Bot::Config).tap do |cfg|
        allow(cfg).to receive(:telegram_enabled?).and_return(true)
        allow(cfg).to receive(:telegram_event_enabled?).with(:analysis).and_return(true)
      end
    end

    it "no-ops when the feature is disabled via ENV" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANALYSIS_SMC_ALERT_ENABLED").and_return("false")

      expect { described_class.call(symbol: "BTCUSD") }.not_to raise_error
    end

    it "enqueues evaluation when the Redis gate is acquired" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANALYSIS_SMC_ALERT_ENABLED").and_return(nil)
      allow(Bot::Config).to receive(:load).and_return(telegram_config)
      SymbolConfig.where(symbol: "SMCALRT1").delete_all
      SymbolConfig.create!(symbol: "SMCALRT1", leverage: 10, enabled: true)
      Redis.current.del(gate_key)
      allow(Trading::Analysis::SmcAlertEvaluationJob).to receive(:perform_later)

      described_class.call(symbol: "SMCALRT1")

      expect(Trading::Analysis::SmcAlertEvaluationJob).to have_received(:perform_later).with("SMCALRT1")
    ensure
      Redis.current.del(gate_key)
      SymbolConfig.where(symbol: "SMCALRT1").delete_all
    end

    it "does not enqueue when the Redis gate is already held" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANALYSIS_SMC_ALERT_ENABLED").and_return(nil)
      allow(Bot::Config).to receive(:load).and_return(telegram_config)
      SymbolConfig.where(symbol: "SMCALRT1").delete_all
      SymbolConfig.create!(symbol: "SMCALRT1", leverage: 10, enabled: true)
      Redis.current.set(gate_key, "1", ex: 60)
      allow(Trading::Analysis::SmcAlertEvaluationJob).to receive(:perform_later)

      described_class.call(symbol: "SMCALRT1")

      expect(Trading::Analysis::SmcAlertEvaluationJob).not_to have_received(:perform_later)
    ensure
      Redis.current.del(gate_key)
      SymbolConfig.where(symbol: "SMCALRT1").delete_all
    end
  end

  describe ".parse_prev_flags" do
    it "returns an empty hash and logs when stored state is not valid JSON" do
      allow(Trading::HotPathErrorPolicy).to receive(:log_swallowed_error)

      actual = described_class.send(:parse_prev_flags, "{not json", sym: "BTCUSD")

      expect(actual).to eq({})
      expect(Trading::HotPathErrorPolicy).to have_received(:log_swallowed_error).with(
        hash_including(component: "SmcAlertEvaluator", operation: "parse_prev_flags", symbol: "BTCUSD")
      )
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
