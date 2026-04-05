# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::Analysis::Store do
  let(:redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:current).and_return(redis)
  end

  it "returns parsed JSON when Redis has valid payload" do
    allow(redis).to receive(:get).and_return('{"updated_at":null,"symbols":[],"meta":{}}')

    expect(described_class.read).to include("symbols" => [])
  end

  it "returns empty payload and reports when JSON is invalid" do
    allow(redis).to receive(:get).and_return("not-json{")
    allow(Rails.logger).to receive(:warn)
    allow(Rails.error).to receive(:report)

    out = described_class.read

    expect(out["symbols"]).to eq([])
    expect(out["meta"]["source"]).to eq("none")
    expect(Rails.error).to have_received(:report).with(
      instance_of(JSON::ParserError),
      handled: true,
      context: hash_including("component" => "Analysis::Store", "operation" => "read")
    )
  end
end
