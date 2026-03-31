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
  end
end
