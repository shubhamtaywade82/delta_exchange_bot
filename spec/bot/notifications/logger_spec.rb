# frozen_string_literal: true

require "spec_helper"
require "bot/notifications/logger"
require "json"
require "tmpdir"

RSpec.describe Bot::Notifications::Logger do
  let(:log_file) { File.join(Dir.tmpdir, "test_bot_#{Process.pid}.log") }
  subject(:logger) { described_class.new(file: log_file, level: "info") }

  after { File.delete(log_file) if File.exist?(log_file) }

  it "writes a JSON line to the log file" do
    logger.info("trade_opened", symbol: "BTCUSDT", side: "long")
    lines = File.readlines(log_file)
    expect(lines.size).to eq(1)
    entry = JSON.parse(lines.first)
    expect(entry["event"]).to eq("trade_opened")
    expect(entry["symbol"]).to eq("BTCUSDT")
    expect(entry["level"]).to eq("info")
    expect(entry["ts"]).to match(/\d{4}-\d{2}-\d{2}T/)
  end

  it "does not write debug entries when level is info" do
    logger.debug("noisy_event", detail: "x")
    expect(File.exist?(log_file)).to be(false).or(satisfy { File.read(log_file).strip.empty? })
  end

  it "writes error entries regardless of level" do
    logger.error("crash", message: "boom")
    entry = JSON.parse(File.readlines(log_file).last)
    expect(entry["level"]).to eq("error")
  end
end
