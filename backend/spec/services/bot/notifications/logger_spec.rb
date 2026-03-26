# frozen_string_literal: true

require "rails_helper"
require "json"
require "tmpdir"

RSpec.describe Bot::Notifications::Logger do
  let(:log_file) { File.join(Dir.tmpdir, "test_bot_#{Process.pid}_#{rand(9999)}.log") }
  subject(:logger) { described_class.new(file: log_file, level: "info") }

  after do
    logger.close rescue nil
    File.delete(log_file) if File.exist?(log_file)
  end

  it "writes a JSON line to the log file" do
    logger.info("trade_opened", symbol: "BTCUSD", side: "long")
    lines = File.readlines(log_file)
    expect(lines.size).to eq(1)
    entry = JSON.parse(lines.first)
    expect(entry["event"]).to eq("trade_opened")
    expect(entry["symbol"]).to eq("BTCUSD")
    expect(entry["level"]).to eq("info")
    expect(entry["ts"]).to match(/\d{4}-\d{2}-\d{2}T/)
  end

  it "does not write debug entries when level is info" do
    logger.debug("noisy_event", detail: "x")
    logger.close
    content = File.exist?(log_file) ? File.read(log_file).strip : ""
    expect(content).to be_empty
  end

  it "writes error entries regardless of level" do
    logger.error("crash", message: "boom")
    entry = JSON.parse(File.readlines(log_file).last)
    expect(entry["level"]).to eq("error")
  end

  it "raises ArgumentError for an unknown log level" do
    expect {
      described_class.new(file: log_file, level: "verbose")
    }.to raise_error(ArgumentError, /Unknown log level/)
  end

  it "is thread-safe under concurrent writes" do
    threads = 10.times.map do |i|
      Thread.new { logger.info("event_#{i}", thread: i) }
    end
    threads.each(&:join)
    logger.close

    lines = File.readlines(log_file)
    expect(lines.size).to eq(10)
    lines.each { |line| expect { JSON.parse(line) }.not_to raise_error }
  end
end
