require "rails_helper"

RSpec.describe Trading::SessionResumer do
  describe ".call" do
    let!(:running_session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
    let!(:stopped_session) { TradingSession.create!(strategy: "multi_timeframe", status: "stopped", capital: 1000.0) }

    before do
      Redis.current.del(described_class::BOOT_LOCK_KEY)
      Redis.current.del("delta_bot_lock:#{running_session.id}")
      allow(DeltaTradingJob).to receive(:perform_later)
    end

    after do
      Redis.current.del("delta_bot_lock:#{running_session.id}")
      Redis.current.del(described_class::BOOT_LOCK_KEY)
    end

    it "enqueues only running sessions without active lock" do
      described_class.call

      expect(DeltaTradingJob).to have_received(:perform_later).with(running_session.id).once
      expect(DeltaTradingJob).not_to have_received(:perform_later).with(stopped_session.id)
    end

    it "skips running sessions that already have lock" do
      Redis.current.set("delta_bot_lock:#{running_session.id}", 1, ex: 60)

      described_class.call

      expect(DeltaTradingJob).not_to have_received(:perform_later)
    end

    it "runs only once while boot lock is active" do
      described_class.call
      described_class.call

      expect(DeltaTradingJob).to have_received(:perform_later).once
    end

    it "returns 0 and reports when resuming raises" do
      allow(DeltaTradingJob).to receive(:perform_later).and_raise(StandardError, "queue unavailable")
      allow(Rails.error).to receive(:report)

      expect(described_class.call).to eq(0)

      expect(Rails.error).to have_received(:report).with(
        an_object_having_attributes(message: "queue unavailable"),
        handled: true,
        context: hash_including("component" => "SessionResumer", "operation" => "call")
      )
    end
  end
end
