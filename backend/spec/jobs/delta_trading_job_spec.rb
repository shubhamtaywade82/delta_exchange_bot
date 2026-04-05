require "rails_helper"

RSpec.describe DeltaTradingJob, type: :job do
  let(:session) do
    TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0)
  end
  let(:runner_dbl) { instance_double(Trading::Runner, start: nil, stop: nil) }

  before do
    # Session IDs often repeat across examples (transactional DB); another spec may leave this lock.
    Redis.current.del("delta_bot_lock:#{session.id}")
    allow(Trading::Runner).to receive(:new).and_return(runner_dbl)
  end

  after do
    Redis.current.del("delta_bot_lock:#{session.id}")
  end

  it "starts a Trading::Runner for the given session" do
    described_class.new.perform(session.id)
    expect(Trading::Runner).to have_received(:new).with(session_id: session.id)
    expect(runner_dbl).to have_received(:start)
  end

  it "does not start runner when lock is already held" do
    Redis.current.set("delta_bot_lock:#{session.id}", 1, nx: true, ex: 86_400)
    described_class.new.perform(session.id)
    expect(runner_dbl).not_to have_received(:start)
  end

  it "releases the Redis lock after runner completes" do
    described_class.new.perform(session.id)
    expect(Redis.current.get("delta_bot_lock:#{session.id}")).to be_nil
  end

  it "releases lock even when runner raises" do
    allow(runner_dbl).to receive(:start).and_raise(RuntimeError, "crash")
    expect { described_class.new.perform(session.id) }.to raise_error(RuntimeError)
    expect(Redis.current.get("delta_bot_lock:#{session.id}")).to be_nil
  end

  it "marks session as crashed when runner raises" do
    allow(runner_dbl).to receive(:start).and_raise(RuntimeError, "crash")
    expect { described_class.new.perform(session.id) }.to raise_error(RuntimeError)
    expect(session.reload.status).to eq("crashed")
  end
end
