# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bot::Notifications::TelegramTextChunker do
  describe ".chunk" do
    it "returns a single piece when under the limit" do
      expect(described_class.chunk("hello", max_body_chars: 100)).to eq([ "hello" ])
    end

    it "returns empty array for blank input" do
      expect(described_class.chunk("", max_body_chars: 100)).to eq([])
    end

    it "splits on paragraph breaks when possible" do
      a = "a" * 100
      b = "b" * 100
      text = "#{a}\n\n#{b}"
      chunks = described_class.chunk(text, max_body_chars: 150)
      expect(chunks.size).to be >= 2
      expect(chunks.join).to include("a")
      expect(chunks.join).to include("b")
    end

    it "hard-splits when there are no newlines" do
      text = "x" * 10_000
      chunks = described_class.chunk(text, max_body_chars: 3_800)
      expect(chunks.size).to be > 2
      expect(chunks.join).to eq(text)
    end
  end
end
