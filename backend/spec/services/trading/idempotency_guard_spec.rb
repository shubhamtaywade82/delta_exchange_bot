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

  describe ".exchange_side" do
    it "maps long and buy to buy" do
      expect(described_class.exchange_side(:long)).to eq("buy")
      expect(described_class.exchange_side("buy")).to eq("buy")
    end

    it "maps short and sell to sell" do
      expect(described_class.exchange_side(:short)).to eq("sell")
      expect(described_class.exchange_side("sell")).to eq("sell")
    end
  end

  describe ".key_for_signal" do
    let(:signal) do
      Trading::Events::SignalGenerated.new(
        symbol: "BTCUSD",
        side: "long",
        entry_price: 1.0,
        candle_timestamp: Time.zone.at(1_711_440_000),
        strategy: "mtf",
        session_id: 1
      )
    end

    it "uses exchange side so long matches buy in the key" do
      long_key = described_class.key_for_signal(signal)
      buy_key = described_class.key(
        symbol: "BTCUSD",
        side: "buy",
        timestamp: signal.candle_timestamp.to_i
      )
      expect(long_key).to eq(buy_key)
    end
  end
end
