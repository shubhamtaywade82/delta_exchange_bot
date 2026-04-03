# spec/services/trading/event_bus_spec.rb
require "rails_helper"

RSpec.describe Trading::EventBus do
  before { described_class.reset! }
  after  { described_class.reset! }

  it "calls subscriber when event is published" do
    received = nil
    described_class.subscribe(:test_event) { |payload| received = payload }
    described_class.publish(:test_event, { value: 42 })
    expect(received).to eq({ value: 42 })
  end

  it "calls multiple subscribers for the same event" do
    results = []
    described_class.subscribe(:multi) { |p| results << "a:#{p}" }
    described_class.subscribe(:multi) { |p| results << "b:#{p}" }
    described_class.publish(:multi, "x")
    expect(results).to contain_exactly("a:x", "b:x")
  end

  it "does not call subscribers for different events" do
    called = false
    described_class.subscribe(:other_event) { called = true }
    described_class.publish(:unrelated, {})
    expect(called).to be false
  end

  it "reset! clears all subscribers" do
    called = false
    described_class.subscribe(:evt) { called = true }
    described_class.reset!
    described_class.publish(:evt, {})
    expect(called).to be false
  end

  it "invokes later handlers when an earlier handler raises" do
    seen = []
    described_class.subscribe(:boom) { raise StandardError, "handler failed" }
    described_class.subscribe(:boom) { |p| seen << p }
    allow(Rails.logger).to receive(:error)
    allow(Rails.error).to receive(:report)

    described_class.publish(:boom, :payload)

    expect(seen).to eq([:payload])
    expect(Rails.error).to have_received(:report).with(
      an_object_having_attributes(message: "handler failed"),
      handled: true,
      context: hash_including(
        "component" => "EventBus",
        "event_type" => "boom",
        "payload_type" => "Symbol"
      )
    )
  end

  it "is thread-safe under concurrent publish" do
    results = []
    mutex = Mutex.new
    described_class.subscribe(:concurrent) { |p| mutex.synchronize { results << p } }

    threads = 10.times.map { |i| Thread.new { described_class.publish(:concurrent, i) } }
    threads.each(&:join)

    expect(results.size).to eq(10)
  end
end
