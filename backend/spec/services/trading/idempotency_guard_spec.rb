require "rails_helper"

RSpec.describe Trading::IdempotencyGuard do
  let(:key) { described_class.key(symbol: "BTCUSD", side: "buy", timestamp: 1_711_440_000) }

  after { described_class.release(key) }

  it "generates a deterministic key from signal attributes" do
    k1 = described_class.key(symbol: "BTCUSD", side: "buy", timestamp: 1_711_440_000)
    k2 = described_class.key(symbol: "BTCUSD", side: "buy", timestamp: 1_711_440_000)
    expect(k1).to eq(k2)
  end

  it "acquire returns truthy on first call" do
    expect(described_class.acquire(key)).to be_truthy
  end

  it "acquire returns falsy on second call (duplicate prevention)" do
    described_class.acquire(key)
    expect(described_class.acquire(key)).to be_falsy
  end

  it "release allows re-acquire" do
    described_class.acquire(key)
    described_class.release(key)
    expect(described_class.acquire(key)).to be_truthy
  end
end
