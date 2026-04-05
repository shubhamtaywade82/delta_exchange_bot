# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::PaperTrading do
  describe ".enabled?" do
    it "falls back to non-production default when config load fails" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("EXECUTION_MODE").and_return("")
      allow(Bot::Config).to receive(:load).and_raise(StandardError, "config unavailable")
      allow(Rails.error).to receive(:report)

      expect(described_class.enabled?).to eq(!Rails.env.production?)

      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "config unavailable"),
        handled: true,
        context: hash_including("component" => "PaperTrading", "operation" => "enabled?")
      )
    end
  end
end
