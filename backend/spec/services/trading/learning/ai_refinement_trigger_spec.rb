require "rails_helper"

RSpec.describe Trading::Learning::AiRefinementTrigger do
  describe ".call" do
    before do
      Redis.current.del(described_class::LOCK_KEY)
      allow(Trading::Learning::AiRefinementJob).to receive(:perform_later)
    end

    it "enqueues refinement when lock is free" do
      described_class.call(reason: "trade_closed:1")

      expect(Trading::Learning::AiRefinementJob).to have_received(:perform_later).once
    end

    it "does not enqueue when reason is blank" do
      described_class.call(reason: "")

      expect(Trading::Learning::AiRefinementJob).not_to have_received(:perform_later)
    end

    it "throttles enqueue while lock is active" do
      2.times { described_class.call(reason: "setting_change:learning.epsilon") }

      expect(Trading::Learning::AiRefinementJob).to have_received(:perform_later).once
    end
  end
end
