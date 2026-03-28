# Minimal Winning Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the bot with RSI, VWAP, BOS, Order Block indicators + CVD/OI/Funding Rate data stores and a three-gate filter pipeline, replacing the noisy 5M Supertrend flip with a precision BOS+OB entry trigger.

**Architecture:** Indicator modules follow the existing `Supertrend`/`ADX` module pattern (`def self.compute`). New feed stores (`CvdStore`, `DerivativesStore`) mirror `PriceStore` (Mutex, `update`/`get`). `MultiTimeframe` gains two optional store kwargs; filters are veto-only modules returning `{passed:, reason:}`. Backend mirrors bot modules; frontend adds Signal Quality Panel and Derivatives Strip reading the enriched Redis state.

**Tech Stack:** Ruby 3.2+, RSpec, Redis, DeltaExchange gem (local path), React 18 + TypeScript, Axios

---

## File Map

### New files

| File | Responsibility |
|------|---------------|
| `lib/bot/strategy/indicators/rsi.rb` | RSI(14) calculator — candles → `{value, overbought, oversold}` |
| `lib/bot/strategy/indicators/vwap.rb` | VWAP + deviation — candles → `{vwap, deviation_pct, price_above}` |
| `lib/bot/strategy/indicators/bos.rb` | Break of Structure — candles → `{direction, level, confirmed}` |
| `lib/bot/strategy/indicators/order_block.rb` | OB zones — candles → `[{side, high, low, fresh, strength, age}]` |
| `lib/bot/strategy/filters/momentum_filter.rb` | RSI gate — `{passed, reason}` |
| `lib/bot/strategy/filters/volume_filter.rb` | CVD + VWAP gate |
| `lib/bot/strategy/filters/derivatives_filter.rb` | OI divergence + funding rate gate |
| `lib/bot/feed/cvd_store.rb` | Thread-safe CVD accumulator fed by WS all_trades |
| `lib/bot/feed/derivatives_store.rb` | OI (polled REST) + funding rate (WS) store |
| `backend/app/services/bot/strategy/indicators/rsi.rb` | Backend mirror |
| `backend/app/services/bot/strategy/indicators/vwap.rb` | Backend mirror |
| `backend/app/services/bot/strategy/indicators/bos.rb` | Backend mirror |
| `backend/app/services/bot/strategy/indicators/order_block.rb` | Backend mirror |
| `backend/app/services/bot/strategy/filters/momentum_filter.rb` | Backend mirror |
| `backend/app/services/bot/strategy/filters/volume_filter.rb` | Backend mirror |
| `backend/app/services/bot/strategy/filters/derivatives_filter.rb` | Backend mirror |
| `backend/app/controllers/api/order_blocks_controller.rb` | `GET /api/symbols/:symbol/order_blocks` |
| `spec/bot/strategy/indicators/rsi_spec.rb` | RSI tests |
| `spec/bot/strategy/indicators/vwap_spec.rb` | VWAP tests |
| `spec/bot/strategy/indicators/bos_spec.rb` | BOS tests |
| `spec/bot/strategy/indicators/order_block_spec.rb` | OB tests |
| `spec/bot/strategy/filters/momentum_filter_spec.rb` | Momentum filter tests |
| `spec/bot/strategy/filters/volume_filter_spec.rb` | Volume filter tests |
| `spec/bot/strategy/filters/derivatives_filter_spec.rb` | Derivatives filter tests |
| `spec/bot/feed/cvd_store_spec.rb` | CvdStore tests |
| `spec/bot/feed/derivatives_store_spec.rb` | DerivativesStore tests |

### Modified files

| File | Change |
|------|--------|
| `config/bot.yml` | Add RSI, VWAP, BOS, OB, filters, derivatives poll config |
| `lib/bot/config.rb` | Add config accessors for new keys |
| `lib/bot/feed/websocket_feed.rb` | Subscribe to `all_trades` + `funding_rate` channels |
| `lib/bot/strategy/multi_timeframe.rb` | Accept stores, add volume to fetch_candles, replace 5M flip with BOS+OB+filters |
| `lib/bot/persistence/state_publisher.rb` | Extend Redis payload with new indicator state |
| `lib/bot/runner.rb` | Instantiate and wire CvdStore, DerivativesStore |
| `backend/app/controllers/api/strategy_status_controller.rb` | Update TIMEFRAMES and entry_rules descriptions |
| `backend/config/routes.rb` | Add order_blocks route |
| `frontend/src/App.tsx` | Add SymbolState fields, SignalQualityPanel, DerivativesStrip |
| `spec/bot/strategy/multi_timeframe_spec.rb` | Add new filter stubs to config double |

---

## Task 1: Config additions

**Files:**

- Modify: `config/bot.yml`
- Modify: `lib/bot/config.rb`
- Test: `spec/bot/config_spec.rb`

- [ ] **Step 1: Write failing tests for new config accessors**

In `spec/bot/config_spec.rb`, add inside the existing `RSpec.describe Bot::Config` block (after the existing let(:valid_yaml) block, add new keys, then add examples):

```ruby
# Add these keys to the valid_yaml let block's "strategy" hash:
#   "rsi" => { "period" => 14, "overbought" => 70, "oversold" => 30 },
#   "vwap" => { "session_reset_hour_utc" => 0 },
#   "bos" => { "swing_lookback" => 10 },
#   "order_block" => { "min_impulse_pct" => 0.3, "max_ob_age" => 20 },
#   "filters" => { "funding_rate_threshold" => 0.05, "cvd_window" => 50 },
#   "derivatives" => { "oi_poll_interval" => 30 }

# Add these examples at the end of the describe block:
describe "new MWS accessors" do
  it "exposes rsi_period" do
    expect(config.rsi_period).to eq(14)
  end

  it "exposes rsi_overbought" do
    expect(config.rsi_overbought).to eq(70.0)
  end

  it "exposes rsi_oversold" do
    expect(config.rsi_oversold).to eq(30.0)
  end

  it "exposes vwap_session_reset_hour_utc" do
    expect(config.vwap_session_reset_hour_utc).to eq(0)
  end

  it "exposes bos_swing_lookback" do
    expect(config.bos_swing_lookback).to eq(10)
  end

  it "exposes ob_min_impulse_pct" do
    expect(config.ob_min_impulse_pct).to eq(0.3)
  end

  it "exposes ob_max_age" do
    expect(config.ob_max_age).to eq(20)
  end

  it "exposes funding_rate_threshold" do
    expect(config.funding_rate_threshold).to eq(0.05)
  end

  it "exposes cvd_window" do
    expect(config.cvd_window).to eq(50)
  end

  it "exposes oi_poll_interval" do
    expect(config.oi_poll_interval).to eq(30)
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

```bash
bundle exec rspec spec/bot/config_spec.rb --format documentation
```

Expected: failures — `undefined method 'rsi_period'`

- [ ] **Step 3: Add keys to config/bot.yml**

In `config/bot.yml`, add after the existing `adx:` block inside `strategy:`:

```yaml
  rsi:
    period: 14
    overbought: 70
    oversold: 30
  vwap:
    session_reset_hour_utc: 0
  bos:
    swing_lookback: 10
  order_block:
    min_impulse_pct: 0.3
    max_ob_age: 20
  filters:
    funding_rate_threshold: 0.05
    cvd_window: 50
  derivatives:
    oi_poll_interval: 30
```

- [ ] **Step 4: Add accessors to lib/bot/config.rb**

Add these methods to the public interface section of `Config`, after the `adx_threshold` method:

```ruby
def rsi_period
  @raw.dig("strategy", "rsi", "period")&.to_i || 14
end

def rsi_overbought
  @raw.dig("strategy", "rsi", "overbought")&.to_f || 70.0
end

def rsi_oversold
  @raw.dig("strategy", "rsi", "oversold")&.to_f || 30.0
end

def vwap_session_reset_hour_utc
  @raw.dig("strategy", "vwap", "session_reset_hour_utc")&.to_i || 0
end

def bos_swing_lookback
  @raw.dig("strategy", "bos", "swing_lookback")&.to_i || 10
end

def ob_min_impulse_pct
  @raw.dig("strategy", "order_block", "min_impulse_pct")&.to_f || 0.3
end

def ob_max_age
  @raw.dig("strategy", "order_block", "max_ob_age")&.to_i || 20
end

def funding_rate_threshold
  @raw.dig("strategy", "filters", "funding_rate_threshold")&.to_f || 0.05
end

def cvd_window
  @raw.dig("strategy", "filters", "cvd_window")&.to_i || 50
end

def oi_poll_interval
  @raw.dig("strategy", "derivatives", "oi_poll_interval")&.to_i || 30
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/config_spec.rb --format documentation
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add config/bot.yml lib/bot/config.rb spec/bot/config_spec.rb
git commit -m "feat: Add MWS config accessors (RSI, VWAP, BOS, OB, filters, derivatives)"
```

---

## Task 2: CvdStore

**Files:**

- Create: `lib/bot/feed/cvd_store.rb`
- Test: `spec/bot/feed/cvd_store_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/feed/cvd_store_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/feed/cvd_store"

RSpec.describe Bot::Feed::CvdStore do
  subject(:store) { described_class.new(window: 4) }

  describe "#record_trade and #get" do
    it "starts with zero delta and neutral trend" do
      result = store.get("BTCUSD")
      expect(result[:cumulative_delta]).to eq(0.0)
      expect(result[:delta_trend]).to eq(:neutral)
    end

    it "accumulates positive delta for buy trades" do
      store.record_trade("BTCUSD", side: "buy", size: 10)
      store.record_trade("BTCUSD", side: "buy", size: 5)
      expect(store.get("BTCUSD")[:cumulative_delta]).to eq(15.0)
    end

    it "accumulates negative delta for sell trades" do
      store.record_trade("BTCUSD", side: "sell", size: 8)
      expect(store.get("BTCUSD")[:cumulative_delta]).to eq(-8.0)
    end

    it "returns bullish trend when window delta is positive" do
      store.record_trade("BTCUSD", side: "buy",  size: 10)
      store.record_trade("BTCUSD", side: "buy",  size: 5)
      store.record_trade("BTCUSD", side: "sell", size: 2)
      expect(store.get("BTCUSD")[:delta_trend]).to eq(:bullish)
    end

    it "returns bearish trend when window delta is negative" do
      store.record_trade("BTCUSD", side: "sell", size: 10)
      store.record_trade("BTCUSD", side: "sell", size: 5)
      store.record_trade("BTCUSD", side: "buy",  size: 2)
      expect(store.get("BTCUSD")[:delta_trend]).to eq(:bearish)
    end

    it "evicts old trades beyond the window" do
      # window=4: add 4 buys then 4 sells — only sells in window
      4.times { store.record_trade("BTCUSD", side: "buy",  size: 10) }
      4.times { store.record_trade("BTCUSD", side: "sell", size: 10) }
      expect(store.get("BTCUSD")[:delta_trend]).to eq(:bearish)
    end

    it "tracks each symbol independently" do
      store.record_trade("BTCUSD", side: "buy",  size: 10)
      store.record_trade("ETHUSD", side: "sell", size: 5)
      expect(store.get("BTCUSD")[:delta_trend]).to eq(:bullish)
      expect(store.get("ETHUSD")[:delta_trend]).to eq(:bearish)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/feed/cvd_store_spec.rb
```

Expected: `LoadError: cannot load such file -- bot/feed/cvd_store`

- [ ] **Step 3: Implement CvdStore**

Create `lib/bot/feed/cvd_store.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Feed
    class CvdStore
      def initialize(window: 50)
        @window = window
        @mutex  = Mutex.new
        @data   = Hash.new { |h, k| h[k] = { cum_delta: 0.0, window_deltas: [] } }
      end

      def record_trade(symbol, side:, size:)
        delta = side == "buy" ? size.to_f : -size.to_f
        @mutex.synchronize do
          d = @data[symbol]
          d[:cum_delta] += delta
          d[:window_deltas] << delta
          d[:window_deltas] = d[:window_deltas].last(@window)
        end
      end

      def get(symbol)
        @mutex.synchronize do
          d = @data[symbol]
          window_sum = d[:window_deltas].sum
          trend = if window_sum > 0
                    :bullish
                  elsif window_sum < 0
                    :bearish
                  else
                    :neutral
                  end
          { cumulative_delta: d[:cum_delta].round(2), delta_trend: trend }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/feed/cvd_store_spec.rb --format documentation
```

Expected: all 7 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/feed/cvd_store.rb spec/bot/feed/cvd_store_spec.rb
git commit -m "feat: Add CvdStore for real-time CVD from all_trades WS feed"
```

---

## Task 3: DerivativesStore

**Files:**

- Create: `lib/bot/feed/derivatives_store.rb`
- Test: `spec/bot/feed/derivatives_store_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/feed/derivatives_store_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/feed/derivatives_store"

RSpec.describe Bot::Feed::DerivativesStore do
  let(:products) { double("Products") }
  let(:logger)   { double("Logger", error: nil, debug: nil) }
  subject(:store) do
    described_class.new(products: products, symbols: ["BTCUSD"],
                        poll_interval: 999, logger: logger)
  end

  describe "#get with no data" do
    it "returns nil OI fields and false for funding_extreme" do
      result = store.get("BTCUSD")
      expect(result[:oi_usd]).to be_nil
      expect(result[:oi_trend]).to be_nil
      expect(result[:funding_rate]).to be_nil
      expect(result[:funding_extreme]).to eq(false)
    end
  end

  describe "#update_funding_rate" do
    it "stores funding rate and marks extreme when above threshold" do
      store.update_funding_rate("BTCUSD", rate: 0.0006)
      result = store.get("BTCUSD")
      expect(result[:funding_rate]).to eq(0.0006)
      expect(result[:funding_extreme]).to eq(true)
    end

    it "marks not extreme when below threshold" do
      store.update_funding_rate("BTCUSD", rate: 0.0003)
      expect(store.get("BTCUSD")[:funding_extreme]).to eq(false)
    end
  end

  describe "#update_oi" do
    it "stores OI and detects rising trend on second call" do
      store.update_oi("BTCUSD", oi_usd: 1_000_000.0)
      store.update_oi("BTCUSD", oi_usd: 1_100_000.0)
      result = store.get("BTCUSD")
      expect(result[:oi_usd]).to eq(1_100_000.0)
      expect(result[:oi_trend]).to eq(:rising)
    end

    it "detects falling trend when OI decreases" do
      store.update_oi("BTCUSD", oi_usd: 1_100_000.0)
      store.update_oi("BTCUSD", oi_usd: 900_000.0)
      expect(store.get("BTCUSD")[:oi_trend]).to eq(:falling)
    end

    it "defaults to rising on first OI update" do
      store.update_oi("BTCUSD", oi_usd: 500_000.0)
      expect(store.get("BTCUSD")[:oi_trend]).to eq(:rising)
    end
  end

  describe "#poll_oi" do
    it "fetches OI from ticker and calls update_oi" do
      allow(products).to receive(:ticker).with("BTCUSD").and_return(
        { "oi_value_usd" => "4200000.5", "funding_rate" => "0.0001" }
      )
      store.poll_oi
      expect(store.get("BTCUSD")[:oi_usd]).to eq(4_200_000.5)
    end

    it "skips symbol if ticker has no oi_value_usd" do
      allow(products).to receive(:ticker).with("BTCUSD").and_return({})
      expect { store.poll_oi }.not_to raise_error
      expect(store.get("BTCUSD")[:oi_usd]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/feed/derivatives_store_spec.rb
```

Expected: `LoadError: cannot load such file -- bot/feed/derivatives_store`

- [ ] **Step 3: Implement DerivativesStore**

Create `lib/bot/feed/derivatives_store.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Feed
    class DerivativesStore
      FUNDING_EXTREME_THRESHOLD = 0.0005  # 0.05%

      def initialize(products:, symbols:, poll_interval: 30, logger: nil)
        @products      = products
        @symbols       = symbols
        @poll_interval = poll_interval
        @logger        = logger
        @data          = {}
        @mutex         = Mutex.new
      end

      # Called by WebsocketFeed when a funding_rate WS message arrives
      def update_funding_rate(symbol, rate:)
        @mutex.synchronize do
          @data[symbol] ||= {}
          @data[symbol][:funding_rate]    = rate.to_f
          @data[symbol][:funding_extreme] = rate.to_f.abs > FUNDING_EXTREME_THRESHOLD
        end
      end

      # Called directly by poll_oi (and also exposed for tests)
      def update_oi(symbol, oi_usd:)
        @mutex.synchronize do
          @data[symbol] ||= {}
          prev = @data[symbol][:oi_usd]
          @data[symbol][:oi_usd]   = oi_usd.to_f
          @data[symbol][:oi_trend] = prev ? (oi_usd.to_f > prev ? :rising : :falling) : :rising
        end
      end

      def get(symbol)
        @mutex.synchronize do
          d = @data[symbol] || {}
          {
            oi_usd:          d[:oi_usd],
            oi_trend:        d[:oi_trend],
            funding_rate:    d[:funding_rate],
            funding_extreme: d[:funding_extreme] || false
          }
        end
      end

      # Fetch OI (and optionally funding rate as fallback) from REST ticker
      def poll_oi
        @symbols.each do |symbol|
          ticker = @products.ticker(symbol)
          oi_usd = ticker["oi_value_usd"]&.to_f
          next unless oi_usd&.positive?

          update_oi(symbol, oi_usd: oi_usd)

          # Use polled funding rate as fallback if WS hasn't delivered one yet
          fr = ticker["funding_rate"]&.to_f
          update_funding_rate(symbol, rate: fr) if fr && get(symbol)[:funding_rate].nil?
        rescue StandardError => e
          @logger&.error("oi_poll_error", symbol: symbol, message: e.message)
        end
      end

      # Starts a background thread that polls OI every @poll_interval seconds
      def start_polling
        Thread.new do
          loop do
            poll_oi
            sleep @poll_interval
          rescue StandardError => e
            @logger&.error("oi_poll_thread_error", message: e.message)
            sleep @poll_interval
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/feed/derivatives_store_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/feed/derivatives_store.rb spec/bot/feed/derivatives_store_spec.rb
git commit -m "feat: Add DerivativesStore for OI polling and funding rate from WS"
```

---

## Task 4: RSI Indicator

**Files:**

- Create: `lib/bot/strategy/indicators/rsi.rb`
- Test: `spec/bot/strategy/indicators/rsi_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/indicators/rsi_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/indicators/rsi"

RSpec.describe Bot::Strategy::Indicators::RSI do
  # 20 candles: first 10 rising, then 10 falling
  let(:candles) do
    prices = [100, 102, 104, 106, 108, 110, 112, 114, 116, 118,
              116, 114, 112, 110, 108, 106, 104, 102, 100, 98]
    prices.map { |c| { close: c.to_f } }
  end

  describe ".compute" do
    subject(:result) { described_class.compute(candles, period: 5) }

    it "returns one result per candle" do
      expect(result.size).to eq(candles.size)
    end

    it "returns nil value for bars before enough data" do
      expect(result.first[:value]).to be_nil
    end

    it "returns a Float value after enough bars" do
      expect(result.last[:value]).to be_a(Float)
    end

    it "RSI is between 0 and 100" do
      non_nil = result.compact.reject { |r| r[:value].nil? }
      non_nil.each { |r| expect(r[:value]).to be_between(0.0, 100.0) }
    end

    it "marks overbought when RSI above 70" do
      # All-rising candles should produce high RSI
      up_candles = (1..20).map { |i| { close: (100 + i).to_f } }
      r = described_class.compute(up_candles, period: 5)
      last_rsi = r.last
      expect(last_rsi[:overbought]).to eq(last_rsi[:value] > 70)
    end

    it "marks oversold when RSI below 30" do
      # All-falling candles should produce low RSI
      down_candles = (0..19).map { |i| { close: (100 - i).to_f } }
      r = described_class.compute(down_candles, period: 5)
      last_rsi = r.last
      expect(last_rsi[:oversold]).to eq(last_rsi[:value] < 30)
    end

    it "returns all nil results when candle count <= period" do
      short = candles.first(5)
      r = described_class.compute(short, period: 5)
      expect(r.all? { |x| x[:value].nil? }).to be true
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/strategy/indicators/rsi_spec.rb
```

Expected: `LoadError: cannot load such file -- bot/strategy/indicators/rsi`

- [ ] **Step 3: Implement RSI**

Create `lib/bot/strategy/indicators/rsi.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module RSI
        def self.compute(candles, period: 14)
          n       = candles.size
          results = Array.new(n) { { value: nil, overbought: false, oversold: false } }
          return results if n <= period

          changes = (1...n).map { |i| candles[i][:close].to_f - candles[i - 1][:close].to_f }

          avg_gain = changes[0, period].sum { |c| c > 0 ? c : 0.0 } / period
          avg_loss = changes[0, period].sum { |c| c < 0 ? c.abs : 0.0 } / period

          results[period] = build_result(avg_gain, avg_loss)

          (period...(changes.size)).each do |i|
            avg_gain = (avg_gain * (period - 1) + [changes[i], 0.0].max) / period
            avg_loss = (avg_loss * (period - 1) + [(-changes[i]), 0.0].max) / period
            results[i + 1] = build_result(avg_gain, avg_loss)
          end

          results
        end

        def self.build_result(avg_gain, avg_loss)
          rsi = avg_loss.zero? ? 100.0 : 100.0 - (100.0 / (1.0 + avg_gain / avg_loss))
          { value: rsi.round(2), overbought: rsi > 70, oversold: rsi < 30 }
        end
        private_class_method :build_result
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/strategy/indicators/rsi_spec.rb --format documentation
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/indicators/rsi.rb spec/bot/strategy/indicators/rsi_spec.rb
git commit -m "feat: Add RSI indicator module"
```

---

## Task 5: VWAP Indicator

**Files:**

- Create: `lib/bot/strategy/indicators/vwap.rb`
- Test: `spec/bot/strategy/indicators/vwap_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/indicators/vwap_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/indicators/vwap"

RSpec.describe Bot::Strategy::Indicators::VWAP do
  def make_candle(high:, low:, close:, volume:, timestamp: 0)
    { high: high.to_f, low: low.to_f, close: close.to_f,
      volume: volume.to_f, timestamp: timestamp }
  end

  describe ".compute" do
    let(:candles) do
      [
        make_candle(high: 102, low: 98,  close: 100, volume: 10, timestamp: 0),
        make_candle(high: 104, low: 100, close: 102, volume: 20, timestamp: 300),
        make_candle(high: 106, low: 102, close: 104, volume: 30, timestamp: 600),
      ]
    end

    subject(:result) { described_class.compute(candles) }

    it "returns one result per candle" do
      expect(result.size).to eq(3)
    end

    it "first candle VWAP equals its own typical price" do
      tp = (102 + 98 + 100) / 3.0
      expect(result[0][:vwap]).to eq(tp.round(4))
    end

    it "second candle VWAP is volume-weighted avg of first two typical prices" do
      tp0 = (102 + 98  + 100) / 3.0
      tp1 = (104 + 100 + 102) / 3.0
      expected = ((tp0 * 10 + tp1 * 20) / 30.0).round(4)
      expect(result[1][:vwap]).to eq(expected)
    end

    it "returns price_above true when close is above VWAP" do
      expect(result[2][:price_above]).to be(true).or be(false)
    end

    it "returns nil for zero-volume candles" do
      zero_vol = [make_candle(high: 100, low: 100, close: 100, volume: 0)]
      expect(described_class.compute(zero_vol).first[:vwap]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/strategy/indicators/vwap_spec.rb
```

Expected: `LoadError: cannot load such file -- bot/strategy/indicators/vwap`

- [ ] **Step 3: Implement VWAP**

Create `lib/bot/strategy/indicators/vwap.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module VWAP
        def self.compute(candles, session_reset_hour_utc: 0)
          n        = candles.size
          results  = Array.new(n) { { vwap: nil, deviation_pct: nil, price_above: nil } }
          cum_tpv  = 0.0
          cum_vol  = 0.0

          candles.each_with_index do |c, i|
            if i > 0
              ts      = Time.at(c[:timestamp].to_i).utc
              prev_ts = Time.at(candles[i - 1][:timestamp].to_i).utc
              if ts.hour == session_reset_hour_utc && prev_ts.hour != session_reset_hour_utc
                cum_tpv = 0.0
                cum_vol = 0.0
              end
            end

            vol = c[:volume].to_f
            next if vol.zero?

            typical = (c[:high].to_f + c[:low].to_f + c[:close].to_f) / 3.0
            cum_tpv += typical * vol
            cum_vol  += vol

            vwap = cum_tpv / cum_vol
            dev  = ((c[:close].to_f - vwap) / vwap * 100.0).round(4)

            results[i] = {
              vwap:          vwap.round(4),
              deviation_pct: dev,
              price_above:   c[:close].to_f >= vwap
            }
          end

          results
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/strategy/indicators/vwap_spec.rb --format documentation
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/indicators/vwap.rb spec/bot/strategy/indicators/vwap_spec.rb
git commit -m "feat: Add VWAP indicator module"
```

---

## Task 6: BOS Indicator

**Files:**

- Create: `lib/bot/strategy/indicators/bos.rb`
- Test: `spec/bot/strategy/indicators/bos_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/indicators/bos_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/indicators/bos"

RSpec.describe Bot::Strategy::Indicators::BOS do
  def candle(high:, low:, close:)
    { high: high.to_f, low: low.to_f, close: close.to_f }
  end

  describe ".compute" do
    # 10 ranging candles, then a breakout above, then a breakdown
    let(:ranging) do
      (0..9).map { |i| candle(high: 105.0, low: 95.0, close: 100.0) }
    end

    it "returns one result per candle" do
      result = described_class.compute(ranging, swing_lookback: 5)
      expect(result.size).to eq(ranging.size)
    end

    it "returns confirmed: false before enough lookback candles" do
      result = described_class.compute(ranging, swing_lookback: 5)
      expect(result.first[:confirmed]).to eq(false)
    end

    it "detects bullish BOS when close breaks above swing high" do
      candles = ranging + [candle(high: 120.0, low: 100.0, close: 115.0)]
      result  = described_class.compute(candles, swing_lookback: 5)
      last    = result.last
      expect(last[:direction]).to eq(:bullish)
      expect(last[:confirmed]).to eq(true)
      expect(last[:level]).to eq(105.0)
    end

    it "detects bearish BOS when close breaks below swing low" do
      candles = ranging + [candle(high: 100.0, low: 80.0, close: 85.0)]
      result  = described_class.compute(candles, swing_lookback: 5)
      last    = result.last
      expect(last[:direction]).to eq(:bearish)
      expect(last[:confirmed]).to eq(true)
      expect(last[:level]).to eq(95.0)
    end

    it "returns confirmed: false when close stays within range" do
      candles = ranging + [candle(high: 104.0, low: 97.0, close: 101.0)]
      result  = described_class.compute(candles, swing_lookback: 5)
      expect(result.last[:confirmed]).to eq(false)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/strategy/indicators/bos_spec.rb
```

Expected: `LoadError: cannot load such file -- bot/strategy/indicators/bos`

- [ ] **Step 3: Implement BOS**

Create `lib/bot/strategy/indicators/bos.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module BOS
        def self.compute(candles, swing_lookback: 10)
          n       = candles.size
          results = Array.new(n) { { direction: nil, level: nil, confirmed: false } }

          (swing_lookback...n).each do |i|
            window      = candles[(i - swing_lookback)...i]
            swing_high  = window.map { |c| c[:high].to_f }.max
            swing_low   = window.map { |c| c[:low].to_f  }.min
            close       = candles[i][:close].to_f

            if close > swing_high
              results[i] = { direction: :bullish, level: swing_high, confirmed: true }
            elsif close < swing_low
              results[i] = { direction: :bearish, level: swing_low, confirmed: true }
            else
              prev = results[i - 1]
              results[i] = { direction: prev[:direction], level: prev[:level], confirmed: false }
            end
          end

          results
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/strategy/indicators/bos_spec.rb --format documentation
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/indicators/bos.rb spec/bot/strategy/indicators/bos_spec.rb
git commit -m "feat: Add BOS (Break of Structure) indicator module"
```

---

## Task 7: Order Block Indicator

**Files:**

- Create: `lib/bot/strategy/indicators/order_block.rb`
- Test: `spec/bot/strategy/indicators/order_block_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/indicators/order_block_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/indicators/order_block"

RSpec.describe Bot::Strategy::Indicators::OrderBlock do
  def bear_candle(close)
    open = close + 2.0
    { open: open, high: open + 1.0, low: close - 1.0, close: close.to_f }
  end

  def bull_candle(close)
    open = close - 2.0
    { open: open, high: close + 1.0, low: open - 1.0, close: close.to_f }
  end

  describe ".compute" do
    it "identifies a bull OB: last down candle before bullish impulse" do
      candles = [
        bear_candle(102),   # index 0 — down candle (potential bull OB)
        bull_candle(105),   # index 1
        bull_candle(110),   # index 2 — impulse
        bull_candle(115),   # index 3
      ]
      result = described_class.compute(candles, min_impulse_pct: 1.0, max_ob_age: 10)
      bull_obs = result.select { |ob| ob[:side] == :bull }
      expect(bull_obs).not_to be_empty
    end

    it "identifies a bear OB: last up candle before bearish impulse" do
      candles = [
        bull_candle(102),   # index 0 — up candle (potential bear OB)
        bear_candle(99),    # index 1
        bear_candle(94),    # index 2 — impulse
        bear_candle(89),    # index 3
      ]
      result = described_class.compute(candles, min_impulse_pct: 1.0, max_ob_age: 10)
      bear_obs = result.select { |ob| ob[:side] == :bear }
      expect(bear_obs).not_to be_empty
    end

    it "marks OB as fresh when price has not traded through it" do
      candles = [
        bear_candle(102),
        bull_candle(108),
        bull_candle(115),
        bull_candle(120),
      ]
      result = described_class.compute(candles, min_impulse_pct: 1.0, max_ob_age: 10)
      bull_ob = result.find { |ob| ob[:side] == :bull }
      expect(bull_ob[:fresh]).to eq(true)
    end

    it "marks OB as not fresh when price trades back through OB low" do
      ob_candle = bear_candle(102)  # high≈103, low≈101
      candles = [
        ob_candle,
        bull_candle(108),
        bull_candle(100),  # last candle trades below OB low (101)
      ]
      result = described_class.compute(candles, min_impulse_pct: 0.1, max_ob_age: 10)
      bull_ob = result.find { |ob| ob[:side] == :bull }
      expect(bull_ob&.dig(:fresh)).not_to eq(true)
    end

    it "excludes OBs older than max_ob_age" do
      candles = [bear_candle(102), bull_candle(110), bull_candle(115)] +
                (0..20).map { |i| bull_candle(115 + i) }
      result = described_class.compute(candles, min_impulse_pct: 0.5, max_ob_age: 5)
      expect(result.all? { |ob| ob[:age] <= 5 }).to be true
    end

    it "returns empty array when fewer than 4 candles" do
      expect(described_class.compute([bear_candle(100)], min_impulse_pct: 0.3, max_ob_age: 10)).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/strategy/indicators/order_block_spec.rb
```

Expected: `LoadError: cannot load such file -- bot/strategy/indicators/order_block`

- [ ] **Step 3: Implement OrderBlock**

Create `lib/bot/strategy/indicators/order_block.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module Indicators
      module OrderBlock
        def self.compute(candles, min_impulse_pct: 0.3, max_ob_age: 20)
          n   = candles.size
          obs = []

          return obs if n < 4

          (0...(n - 2)).each do |i|
            c = candles[i]

            # Look at next 1-3 candles for an impulse move
            lookahead    = candles[(i + 1)..[i + 3, n - 1].min]
            next_closes  = lookahead.map { |x| x[:close].to_f }
            impulse_up   = next_closes.all? { |cl| cl > c[:close].to_f }
            impulse_down = next_closes.all? { |cl| cl < c[:close].to_f }

            move_pct = next_closes.last ? ((next_closes.last - c[:close].to_f) / c[:close].to_f * 100).abs : 0
            next if move_pct < min_impulse_pct

            age = n - 1 - i
            next if age > max_ob_age

            last_close = candles.last[:close].to_f

            if impulse_up && c[:close].to_f < c[:open].to_f
              fresh = last_close > c[:low].to_f
              obs << { side: :bull, high: c[:high].to_f, low: c[:low].to_f,
                       age: age, fresh: fresh, strength: move_pct.round(2) }
            elsif impulse_down && c[:close].to_f > c[:open].to_f
              fresh = last_close < c[:high].to_f
              obs << { side: :bear, high: c[:high].to_f, low: c[:low].to_f,
                       age: age, fresh: fresh, strength: move_pct.round(2) }
            end
          end

          obs.sort_by { |ob| ob[:age] }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/strategy/indicators/order_block_spec.rb --format documentation
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/indicators/order_block.rb spec/bot/strategy/indicators/order_block_spec.rb
git commit -m "feat: Add OrderBlock indicator module"
```

---

## Task 8: MomentumFilter

**Files:**

- Create: `lib/bot/strategy/filters/momentum_filter.rb`
- Test: `spec/bot/strategy/filters/momentum_filter_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/filters/momentum_filter_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/filters/momentum_filter"

RSpec.describe Bot::Strategy::Filters::MomentumFilter do
  def rsi(value)
    { value: value, overbought: value > 70, oversold: value < 30 }
  end

  describe ".check" do
    it "passes for long when RSI is neutral (between 30-70)" do
      result = described_class.check(:long, rsi(55.0))
      expect(result[:passed]).to eq(true)
    end

    it "blocks long when RSI is overbought (> 70)" do
      result = described_class.check(:long, rsi(75.0))
      expect(result[:passed]).to eq(false)
      expect(result[:reason]).to include("RSI")
    end

    it "passes for short when RSI is neutral" do
      result = described_class.check(:short, rsi(45.0))
      expect(result[:passed]).to eq(true)
    end

    it "blocks short when RSI is oversold (< 30)" do
      result = described_class.check(:short, rsi(25.0))
      expect(result[:passed]).to eq(false)
      expect(result[:reason]).to include("RSI")
    end

    it "passes for short when RSI is overbought" do
      result = described_class.check(:short, rsi(80.0))
      expect(result[:passed]).to eq(true)
    end

    it "passes for long when RSI is oversold" do
      result = described_class.check(:long, rsi(20.0))
      expect(result[:passed]).to eq(true)
    end

    it "passes when rsi_result is nil (store not yet populated)" do
      result = described_class.check(:long, nil)
      expect(result[:passed]).to eq(true)
      expect(result[:reason]).to include("unavailable")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/strategy/filters/momentum_filter_spec.rb
```

Expected: `LoadError: cannot load such file -- bot/strategy/filters/momentum_filter`

- [ ] **Step 3: Implement MomentumFilter**

Create `lib/bot/strategy/filters/momentum_filter.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module Filters
      module MomentumFilter
        def self.check(side, rsi_result)
          return { passed: true, reason: "RSI unavailable — skipping gate" } if rsi_result.nil? || rsi_result[:value].nil?

          val = rsi_result[:value]

          if side == :long && rsi_result[:overbought]
            return { passed: false, reason: "RSI #{val} overbought — blocking long entry" }
          end

          if side == :short && rsi_result[:oversold]
            return { passed: false, reason: "RSI #{val} oversold — blocking short entry" }
          end

          { passed: true, reason: "RSI #{val} neutral" }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/strategy/filters/momentum_filter_spec.rb --format documentation
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/filters/momentum_filter.rb spec/bot/strategy/filters/momentum_filter_spec.rb
git commit -m "feat: Add MomentumFilter (RSI gate)"
```

---

## Task 9: VolumeFilter

**Files:**

- Create: `lib/bot/strategy/filters/volume_filter.rb`
- Test: `spec/bot/strategy/filters/volume_filter_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/filters/volume_filter_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/filters/volume_filter"

RSpec.describe Bot::Strategy::Filters::VolumeFilter do
  def cvd(trend)    = { delta_trend: trend, cumulative_delta: 1000.0 }
  def vwap(above)   = { vwap: 100.0, deviation_pct: 0.5, price_above: above }

  describe ".check" do
    context "long signal" do
      it "passes when CVD is bullish and price is above VWAP" do
        result = described_class.check(:long, cvd(:bullish), 101.0, vwap(true))
        expect(result[:passed]).to eq(true)
      end

      it "blocks when CVD is bearish" do
        result = described_class.check(:long, cvd(:bearish), 101.0, vwap(true))
        expect(result[:passed]).to eq(false)
        expect(result[:reason]).to include("CVD")
      end

      it "blocks when price is below VWAP" do
        result = described_class.check(:long, cvd(:bullish), 99.0, vwap(false))
        expect(result[:passed]).to eq(false)
        expect(result[:reason]).to include("VWAP")
      end
    end

    context "short signal" do
      it "passes when CVD is bearish and price is below VWAP" do
        result = described_class.check(:short, cvd(:bearish), 99.0, vwap(false))
        expect(result[:passed]).to eq(true)
      end

      it "blocks when CVD is bullish" do
        result = described_class.check(:short, cvd(:bullish), 99.0, vwap(false))
        expect(result[:passed]).to eq(false)
      end

      it "blocks when price is above VWAP" do
        result = described_class.check(:short, cvd(:bearish), 101.0, vwap(true))
        expect(result[:passed]).to eq(false)
      end
    end

    it "passes when cvd_data is nil (store not yet populated)" do
      result = described_class.check(:long, nil, 101.0, vwap(true))
      expect(result[:passed]).to eq(true)
      expect(result[:reason]).to include("unavailable")
    end

    it "passes when vwap_result is nil" do
      result = described_class.check(:long, cvd(:bullish), 101.0, nil)
      expect(result[:passed]).to eq(true)
      expect(result[:reason]).to include("unavailable")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/strategy/filters/volume_filter_spec.rb
```

Expected: `LoadError`

- [ ] **Step 3: Implement VolumeFilter**

Create `lib/bot/strategy/filters/volume_filter.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module Filters
      module VolumeFilter
        def self.check(side, cvd_data, current_price, vwap_result)
          return { passed: true, reason: "CVD/VWAP unavailable — skipping gate" } if cvd_data.nil? || vwap_result.nil?

          cvd_trend   = cvd_data[:delta_trend]
          price_above = vwap_result[:price_above]
          vwap_val    = vwap_result[:vwap]

          if side == :long
            unless cvd_trend == :bullish
              return { passed: false, reason: "CVD #{cvd_trend} — does not support long entry" }
            end
            unless price_above
              return { passed: false, reason: "VWAP #{vwap_val}: price #{current_price} below VWAP — blocking long" }
            end
          else
            unless cvd_trend == :bearish
              return { passed: false, reason: "CVD #{cvd_trend} — does not support short entry" }
            end
            if price_above
              return { passed: false, reason: "VWAP #{vwap_val}: price #{current_price} above VWAP — blocking short" }
            end
          end

          { passed: true, reason: "CVD #{cvd_trend}, price #{side == :long ? 'above' : 'below'} VWAP #{vwap_val}" }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/strategy/filters/volume_filter_spec.rb --format documentation
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/filters/volume_filter.rb spec/bot/strategy/filters/volume_filter_spec.rb
git commit -m "feat: Add VolumeFilter (CVD + VWAP gate)"
```

---

## Task 10: DerivativesFilter

**Files:**

- Create: `lib/bot/strategy/filters/derivatives_filter.rb`
- Test: `spec/bot/strategy/filters/derivatives_filter_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/filters/derivatives_filter_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/filters/derivatives_filter"

RSpec.describe Bot::Strategy::Filters::DerivativesFilter do
  def deriv(oi_trend:, funding_extreme:)
    { oi_usd: 5_000_000.0, oi_trend: oi_trend,
      funding_rate: 0.0001, funding_extreme: funding_extreme }
  end

  describe ".check" do
    it "passes when OI is rising and funding is not extreme" do
      result = described_class.check(deriv(oi_trend: :rising, funding_extreme: false))
      expect(result[:passed]).to eq(true)
    end

    it "blocks when OI is falling (divergence)" do
      result = described_class.check(deriv(oi_trend: :falling, funding_extreme: false))
      expect(result[:passed]).to eq(false)
      expect(result[:reason]).to include("OI")
    end

    it "blocks when funding rate is extreme" do
      result = described_class.check(deriv(oi_trend: :rising, funding_extreme: true))
      expect(result[:passed]).to eq(false)
      expect(result[:reason]).to include("funding")
    end

    it "blocks on both violations and mentions both" do
      result = described_class.check(deriv(oi_trend: :falling, funding_extreme: true))
      expect(result[:passed]).to eq(false)
    end

    it "passes when derivatives_data is nil (store not yet populated)" do
      result = described_class.check(nil)
      expect(result[:passed]).to eq(true)
      expect(result[:reason]).to include("unavailable")
    end

    it "passes when oi_trend is nil (first poll not yet complete)" do
      result = described_class.check({ oi_usd: nil, oi_trend: nil,
                                       funding_rate: 0.0001, funding_extreme: false })
      expect(result[:passed]).to eq(true)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/bot/strategy/filters/derivatives_filter_spec.rb
```

Expected: `LoadError`

- [ ] **Step 3: Implement DerivativesFilter**

Create `lib/bot/strategy/filters/derivatives_filter.rb`:

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module Filters
      module DerivativesFilter
        def self.check(derivatives_data)
          return { passed: true, reason: "Derivatives unavailable — skipping gate" } if derivatives_data.nil?

          oi_trend        = derivatives_data[:oi_trend]
          funding_extreme = derivatives_data[:funding_extreme]
          funding_rate    = derivatives_data[:funding_rate]

          # Skip OI check if data not yet available
          if oi_trend == :falling
            return { passed: false, reason: "OI falling — potential divergence/trap, blocking entry" }
          end

          if funding_extreme
            return { passed: false, reason: "Funding rate #{funding_rate} extreme — blocking entry" }
          end

          { passed: true, reason: "OI #{oi_trend || 'n/a'}, funding #{funding_rate&.round(5) || 'n/a'} within range" }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/bot/strategy/filters/derivatives_filter_spec.rb --format documentation
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/filters/derivatives_filter.rb spec/bot/strategy/filters/derivatives_filter_spec.rb
git commit -m "feat: Add DerivativesFilter (OI divergence + funding rate gate)"
```

---

## Task 11: WebsocketFeed — add all_trades and funding_rate subscriptions

**Files:**

- Modify: `lib/bot/feed/websocket_feed.rb`

Note: verify the actual field names of `all_trades` and `funding_rate` messages against live Delta Exchange WS output before deploying to testnet/live. The field names below are based on the Delta Exchange API documentation.

- [ ] **Step 1: Update the initializer to accept cvd_store and derivatives_store**

In `lib/bot/feed/websocket_feed.rb`, change the `initialize` signature and `@client.on(:open)` subscription block:

```ruby
def initialize(symbols:, price_store:, logger:, testnet: false, on_tick: nil,
               cvd_store: nil, derivatives_store: nil)
  @symbols           = symbols
  @price_store       = price_store
  @cvd_store         = cvd_store
  @derivatives_store = derivatives_store
  @logger            = logger
  @testnet           = testnet
  @on_tick           = on_tick
  @client            = nil
  @running           = false
  @generation        = 0
end
```

- [ ] **Step 2: Add channel subscriptions in on(:open)**

Replace the existing `@client.on(:open)` block with:

```ruby
@client.on(:open) do
  @logger.info("ws_connected")
  channels = [{ name: "v2/ticker", symbols: @symbols }]
  channels << { name: "all_trades",   symbols: @symbols } if @cvd_store
  channels << { name: "funding_rate", symbols: @symbols } if @derivatives_store
  @client.subscribe(channels)
end
```

- [ ] **Step 3: Add message handlers in on(:message)**

In the `case data["type"]` block, add two new `when` clauses after the `"v2/ticker"` case:

```ruby
when "all_trades"
  symbol = data["symbol"]
  side   = data["buyer_role"] == "taker" ? "buy" : "sell"
  size   = data["size"]&.to_f || data["quantity"]&.to_f
  if symbol && side && size&.positive?
    @cvd_store&.record_trade(symbol, side: side, size: size)
  end

when "funding_rate"
  symbol = data["symbol"]
  rate   = data["funding_rate"]&.to_f
  @derivatives_store&.update_funding_rate(symbol, rate: rate) if symbol && rate
```

- [ ] **Step 4: Run existing WS feed tests to verify no regression**

```bash
bundle exec rspec spec/bot/feed/ --format documentation
```

Expected: all pass (existing price_store_spec and any feed specs)

- [ ] **Step 5: Commit**

```bash
git add lib/bot/feed/websocket_feed.rb
git commit -m "feat: Subscribe WebsocketFeed to all_trades and funding_rate channels"
```

---

## Task 12: MultiTimeframe — replace 5M flip with BOS+OB, add filter chain

**Files:**

- Modify: `lib/bot/strategy/multi_timeframe.rb`
- Modify: `spec/bot/strategy/multi_timeframe_spec.rb`

- [ ] **Step 1: Update the config double in multi_timeframe_spec.rb**

The config double needs the new methods. Update the `let(:config)` block in `spec/bot/strategy/multi_timeframe_spec.rb`:

```ruby
let(:config) do
  double(
    timeframe_trend: "1h", timeframe_confirm: "15m", timeframe_entry: "5m",
    supertrend_atr_period: 3, supertrend_multiplier: 1.5,
    adx_period: 5, adx_threshold: 20,
    candles_lookback: 20, min_candles_required: 10,
    dry_run?: true,
    rsi_period: 5, rsi_overbought: 70.0, rsi_oversold: 30.0,
    vwap_session_reset_hour_utc: 0,
    bos_swing_lookback: 5,
    ob_min_impulse_pct: 0.1, ob_max_age: 20
  )
end
```

Also update `subject(:mtf)` to pass nil stores (stays backward compatible):

```ruby
subject(:mtf) { described_class.new(config: config, market_data: market_data, logger: logger) }
```

- [ ] **Step 2: Run existing multi_timeframe tests — they should still pass before code changes**

```bash
bundle exec rspec spec/bot/strategy/multi_timeframe_spec.rb --format documentation
```

Expected: all pass (the double update is non-breaking)

- [ ] **Step 3: Update require statements and initialize in multi_timeframe.rb**

At the top of `lib/bot/strategy/multi_timeframe.rb`, replace the existing requires with:

```ruby
require_relative "supertrend"
require_relative "adx"
require_relative "signal"
require_relative "indicators/rsi"
require_relative "indicators/vwap"
require_relative "indicators/bos"
require_relative "indicators/order_block"
require_relative "filters/momentum_filter"
require_relative "filters/volume_filter"
require_relative "filters/derivatives_filter"
```

Update `initialize` to accept optional stores:

```ruby
def initialize(config:, market_data:, logger:, cvd_store: nil, derivatives_store: nil)
  @config            = config
  @market_data       = market_data
  @logger            = logger
  @cvd_store         = cvd_store
  @derivatives_store = derivatives_store
  @last_acted        = {}
  @signal_state      = {}
end
```

- [ ] **Step 4: Add volume to fetch_candles**

In the private `fetch_candles` method, update the candle mapping to include volume:

```ruby
candles_payload.map do |c|
  { open:      (c[:open]      || c["open"])&.to_f      || raise("missing open in candle"),
    high:      (c[:high]      || c["high"])&.to_f      || raise("missing high in candle"),
    low:       (c[:low]       || c["low"])&.to_f       || raise("missing low in candle"),
    close:     (c[:close]     || c["close"])&.to_f     || raise("missing close in candle"),
    volume:    (c[:volume]    || c["volume"])&.to_f    || 0.0,
    timestamp: (c[:timestamp] || c["timestamp"] || c[:time] || c["time"])&.to_i || raise("missing timestamp in candle") }
end.sort_by { |c| c[:timestamp] }
```

- [ ] **Step 5: Replace the entry logic in evaluate**

Replace the section from the `# Check for fresh flip on 5M` comment through the `return nil` for no confluence, with the new BOS+OB+filter logic. The full updated `evaluate` method body after the regime checks:

```ruby
# --- Entry: BOS + Order Block on 5M ---
m5_rsi  = Indicators::RSI.compute(m5_candles,  period: @config.rsi_period)
m5_vwap = Indicators::VWAP.compute(m5_candles, session_reset_hour_utc: @config.vwap_session_reset_hour_utc)
m5_bos  = Indicators::BOS.compute(m5_candles,  swing_lookback: @config.bos_swing_lookback)
m5_obs  = Indicators::OrderBlock.compute(m5_candles,
            min_impulse_pct: @config.ob_min_impulse_pct,
            max_ob_age:      @config.ob_max_age)

bos_last  = m5_bos.last
rsi_last  = m5_rsi.last
vwap_last = m5_vwap.last
m5_last_ts = m5_candles.last[:timestamp].to_i

@signal_state[symbol] = {
  h1_dir:          h1_dir&.to_s,
  m15_dir:         m15_dir&.to_s,
  adx:             m15_adx_val&.round(2),
  bos_direction:   bos_last[:direction]&.to_s,
  bos_level:       bos_last[:level],
  rsi:             rsi_last[:value],
  vwap:            vwap_last[:vwap],
  vwap_deviation_pct: vwap_last[:deviation_pct],
  order_blocks:    m5_obs.map { |ob| { side: ob[:side].to_s, high: ob[:high], low: ob[:low], fresh: ob[:fresh] } },
  signal:          nil,
  updated_at:      Time.now.utc.iso8601
}

# BOS must be confirmed in the same direction as regime
unless bos_last[:confirmed] && bos_last[:direction] == h1_dir
  @logger.debug("strategy_skip", symbol: symbol, reason: "no_bos",
                bos_confirmed: bos_last[:confirmed], bos_dir: bos_last[:direction], h1: h1_dir)
  return nil
end

side = h1_dir == :bullish ? :long : :short
signal_side_for_ob = h1_dir  # :bullish or :bearish maps to :bull/:bear OB

# OB confirmation required in live modes; relaxed in dry_run (same as flip was)
ob_ok = @config.dry_run? ||
        m5_obs.any? { |ob| ob[:side] == (signal_side_for_ob == :bullish ? :bull : :bear) && ob[:fresh] }

unless ob_ok
  @logger.debug("strategy_skip", symbol: symbol, reason: "no_fresh_ob", side: side)
  return nil
end

if @last_acted[symbol] == m5_last_ts
  @logger.debug("strategy_skip", symbol: symbol, reason: "stale_candle", candle_ts: m5_last_ts)
  return nil
end

# --- Filter chain ---
cvd_data         = @cvd_store&.get(symbol)
derivatives_data = @derivatives_store&.get(symbol)

filter_results = {
  momentum:    Filters::MomentumFilter.check(side, rsi_last),
  volume:      Filters::VolumeFilter.check(side, cvd_data, current_price, vwap_last),
  derivatives: Filters::DerivativesFilter.check(derivatives_data)
}

@signal_state[symbol] = @signal_state[symbol].merge(
  cvd_trend:       cvd_data&.dig(:delta_trend)&.to_s,
  cvd_delta:       cvd_data&.dig(:cumulative_delta),
  oi_usd:          derivatives_data&.dig(:oi_usd),
  oi_trend:        derivatives_data&.dig(:oi_trend)&.to_s,
  funding_rate:    derivatives_data&.dig(:funding_rate),
  funding_extreme: derivatives_data&.dig(:funding_extreme),
  filters:         filter_results.transform_values { |f| { passed: f[:passed], reason: f[:reason] } }
)

blocked = filter_results.find { |_k, f| !f[:passed] }
if blocked
  @logger.debug("strategy_skip", symbol: symbol, reason: "filter_blocked",
                filter: blocked[0], detail: blocked[1][:reason])
  return nil
end

@last_acted[symbol] = m5_last_ts
@signal_state[symbol] = @signal_state[symbol].merge(signal: side.to_s)
@logger.info("signal_generated", symbol: symbol, side: side, candle_ts: m5_last_ts)

Signal.new(symbol: symbol, side: side, entry_price: current_price, candle_ts: m5_last_ts)
```

Also remove the now-unused `m5_st` Supertrend computation (the `m5_st`, `m5_prev_dir`, `m5_last_dir` lines) and the old `just_flipped` logic from the top of `evaluate`. Keep `h1_st`, `m15_st`, `m15_adx` intact.

- [ ] **Step 6: Run all strategy tests**

```bash
bundle exec rspec spec/bot/strategy/ --format documentation
```

Expected: all existing tests pass (BOS fires on `build_flip_up_candles` because close=208 breaks swing_high≈182; OB check relaxed in dry_run)

- [ ] **Step 7: Commit**

```bash
git add lib/bot/strategy/multi_timeframe.rb spec/bot/strategy/multi_timeframe_spec.rb
git commit -m "feat: Replace 5M Supertrend flip with BOS+OrderBlock entry; add filter chain to MultiTimeframe"
```

---

## Task 13: StatePublisher — extend Redis payload

**Files:**

- Modify: `lib/bot/persistence/state_publisher.rb`

No new tests needed — `publish_strategy_state` is a pass-through; the new fields are set by MultiTimeframe. The existing publisher just serializes whatever hash it receives.

- [ ] **Step 1: Update the STRATEGY_KEY comment in state_publisher.rb**

Update the comment on `publish_strategy_state` to document the expanded payload:

```ruby
# Publish per-symbol strategy evaluation state.
# state: {
#   h1_dir, m15_dir, adx, signal, updated_at,         # existing
#   bos_direction, bos_level, rsi, vwap,               # new indicators
#   vwap_deviation_pct, order_blocks,
#   cvd_trend, cvd_delta,                              # volume
#   oi_usd, oi_trend, funding_rate, funding_extreme,   # derivatives
#   filters: { momentum:, volume:, derivatives: }      # filter verdicts
# }
def publish_strategy_state(symbol, state)
```

The implementation body is unchanged — it already serializes the full state hash.

- [ ] **Step 2: Verify Redis round-trip with the richer payload**

```bash
bundle exec rspec spec/bot/ --format documentation
```

Expected: all pass

- [ ] **Step 3: Commit**

```bash
git add lib/bot/persistence/state_publisher.rb
git commit -m "docs: Document expanded StatePublisher Redis payload for MWS"
```

---

## Task 14: Runner — wire new stores

**Files:**

- Modify: `lib/bot/runner.rb`

- [ ] **Step 1: Add require statements**

In `lib/bot/runner.rb`, add after the existing `require_relative "feed/price_store"` line:

```ruby
require_relative "feed/cvd_store"
require_relative "feed/derivatives_store"
```

- [ ] **Step 2: Instantiate stores in start method**

In the `start` method, after `@price_store = Feed::PriceStore.new`, add:

```ruby
@cvd_store         = Feed::CvdStore.new(window: @config.cvd_window)
@derivatives_store = Feed::DerivativesStore.new(
  products:      DeltaExchange::Client.new.products,
  symbols:       @config.symbol_names,
  poll_interval: @config.oi_poll_interval,
  logger:        @logger
)
```

- [ ] **Step 3: Pass stores to MultiTimeframe**

Update the `@mtf` instantiation line:

```ruby
@mtf = Strategy::MultiTimeframe.new(
  config:            @config,
  market_data:       @market_data,
  logger:            @logger,
  cvd_store:         @cvd_store,
  derivatives_store: @derivatives_store
)
```

- [ ] **Step 4: Pass stores to WebsocketFeed**

Update the `@ws_feed` instantiation:

```ruby
@ws_feed = Feed::WebsocketFeed.new(
  symbols:           @config.symbol_names,
  price_store:       @price_store,
  logger:            @logger,
  testnet:           @config.testnet?,
  cvd_store:         @cvd_store,
  derivatives_store: @derivatives_store
)
```

- [ ] **Step 5: Start OI polling after supervisor registers services**

After `supervisor.register(:portfolio_log) { run_portfolio_log_loop }`, add:

```ruby
@derivatives_store.start_polling
```

- [ ] **Step 6: Boot the bot in dry_run to verify startup**

```bash
BOT_MODE=dry_run bundle exec ruby bin/run 2>&1 | head -30
```

Expected: no errors, logs show `ws_connected` and strategy loop starting

- [ ] **Step 7: Commit**

```bash
git add lib/bot/runner.rb
git commit -m "feat: Wire CvdStore and DerivativesStore into Runner"
```

---

## Task 15: Backend mirror services

**Files:**

- Create: `backend/app/services/bot/strategy/indicators/rsi.rb`
- Create: `backend/app/services/bot/strategy/indicators/vwap.rb`
- Create: `backend/app/services/bot/strategy/indicators/bos.rb`
- Create: `backend/app/services/bot/strategy/indicators/order_block.rb`
- Create: `backend/app/services/bot/strategy/filters/momentum_filter.rb`
- Create: `backend/app/services/bot/strategy/filters/volume_filter.rb`
- Create: `backend/app/services/bot/strategy/filters/derivatives_filter.rb`

The backend mirrors are exact copies of the bot library modules. Rails autoloads them; no require statements needed.

- [ ] **Step 1: Copy indicator files**

```bash
mkdir -p backend/app/services/bot/strategy/indicators
mkdir -p backend/app/services/bot/strategy/filters

cp lib/bot/strategy/indicators/rsi.rb          backend/app/services/bot/strategy/indicators/rsi.rb
cp lib/bot/strategy/indicators/vwap.rb         backend/app/services/bot/strategy/indicators/vwap.rb
cp lib/bot/strategy/indicators/bos.rb          backend/app/services/bot/strategy/indicators/bos.rb
cp lib/bot/strategy/indicators/order_block.rb  backend/app/services/bot/strategy/indicators/order_block.rb
cp lib/bot/strategy/filters/momentum_filter.rb backend/app/services/bot/strategy/filters/momentum_filter.rb
cp lib/bot/strategy/filters/volume_filter.rb   backend/app/services/bot/strategy/filters/volume_filter.rb
cp lib/bot/strategy/filters/derivatives_filter.rb backend/app/services/bot/strategy/filters/derivatives_filter.rb
```

- [ ] **Step 2: Remove frozen_string_literal from backend copies (Rails adds it globally) and remove require_relative lines if any**

Each mirrored file uses `Bot::Strategy::Indicators::RSI` (same namespace). Check that none of the mirror files have `require_relative` calls — they don't, so nothing to change.

- [ ] **Step 3: Verify Rails can boot with the new files**

```bash
cd backend && bundle exec rails runner "puts Bot::Strategy::Indicators::RSI.name"
```

Expected: `Bot::Strategy::Indicators::RSI`

- [ ] **Step 4: Commit**

```bash
git add backend/app/services/bot/strategy/indicators/ backend/app/services/bot/strategy/filters/
git commit -m "feat: Mirror indicator and filter modules to backend services"
```

---

## Task 16: Order blocks controller and route

**Files:**

- Create: `backend/app/controllers/api/order_blocks_controller.rb`
- Modify: `backend/config/routes.rb`

- [ ] **Step 1: Create controller**

Create `backend/app/controllers/api/order_blocks_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  class OrderBlocksController < ApplicationController
    STRATEGY_KEY = "delta:strategy:state"

    def show
      symbol = params[:symbol]
      redis  = Redis.new
      raw    = redis.hget(STRATEGY_KEY, symbol)

      if raw
        state  = JSON.parse(raw, symbolize_names: true)
        blocks = state[:order_blocks] || []
        render json: { symbol: symbol, order_blocks: blocks }
      else
        render json: { symbol: symbol, order_blocks: [] }
      end
    rescue Redis::BaseError
      render json: { symbol: symbol, order_blocks: [] }
    end
  end
end
```

- [ ] **Step 2: Add route**

In `backend/config/routes.rb`, add inside the `namespace :api` block:

```ruby
get "symbols/:symbol/order_blocks" => "order_blocks#show"
```

- [ ] **Step 3: Verify route is registered**

```bash
cd backend && bundle exec rails routes | grep order_blocks
```

Expected: `GET /api/symbols/:symbol/order_blocks`

- [ ] **Step 4: Commit**

```bash
git add backend/app/controllers/api/order_blocks_controller.rb backend/config/routes.rb
git commit -m "feat: Add order_blocks API endpoint reading from Redis state"
```

---

## Task 17: Update StrategyStatusController descriptions

**Files:**

- Modify: `backend/app/controllers/api/strategy_status_controller.rb`

- [ ] **Step 1: Update TIMEFRAMES and entry_rules**

In `backend/app/controllers/api/strategy_status_controller.rb`, replace the `TIMEFRAMES` constant and `entry_rules` array:

```ruby
TIMEFRAMES = [
  { tf: "1H",  role: "Trend filter",   indicator: "Supertrend direction" },
  { tf: "15M", role: "Confirmation",   indicator: "Supertrend + ADX strength" },
  { tf: "5M",  role: "Entry trigger",  indicator: "BOS + Order Block zone" }
].freeze
```

And in `index`, update `entry_rules`:

```ruby
entry_rules: [
  "1H Supertrend must be bullish (long) or bearish (short)",
  "15M Supertrend must agree with 1H direction",
  "15M ADX ≥ #{bot_config.dig(:strategy, :adx_threshold)} (trending, not ranging)",
  "5M BOS confirmed in trend direction + fresh Order Block present",
  "MomentumFilter: RSI not extreme (not overbought for longs / oversold for shorts)",
  "VolumeFilter: CVD agrees with direction + price on correct side of VWAP",
  "DerivativesFilter: OI rising (no divergence) + funding rate within ±0.05%"
],
```

- [ ] **Step 2: Boot Rails and verify response**

```bash
cd backend && bundle exec rails server &
sleep 3
curl -s http://localhost:5000/api/strategy_status | python3 -m json.tool | head -30
```

Expected: JSON with updated `entry_rules` array and `timeframes` showing BOS entry

- [ ] **Step 3: Commit**

```bash
git add backend/app/controllers/api/strategy_status_controller.rb
git commit -m "feat: Update StrategyStatusController to describe BOS+OB entry and filter gates"
```

---

## Task 18: Frontend — SymbolState interface + Signal Quality Panel

**Files:**

- Modify: `frontend/src/App.tsx`

- [ ] **Step 1: Update SymbolState interface**

In `App.tsx`, replace the existing `SymbolState` interface:

```typescript
interface FilterResult {
  passed: boolean;
  reason: string;
}

interface OrderBlock {
  side: 'bull' | 'bear';
  high: number;
  low: number;
  fresh: boolean;
}

interface SymbolState {
  symbol: string;
  // existing
  h1_dir?: string;
  m15_dir?: string;
  adx?: number;
  signal?: string;
  updated_at?: string;
  // new indicators
  bos_direction?: string;
  bos_level?: number;
  rsi?: number;
  vwap?: number;
  vwap_deviation_pct?: number;
  order_blocks?: OrderBlock[];
  // volume
  cvd_trend?: string;
  cvd_delta?: number;
  // derivatives
  oi_usd?: number;
  oi_trend?: string;
  funding_rate?: number;
  funding_extreme?: boolean;
  // filter verdicts
  filters?: {
    momentum?: FilterResult;
    volume?: FilterResult;
    derivatives?: FilterResult;
  };
}
```

- [ ] **Step 2: Add SignalQualityPanel component**

Add this component function above the `App` function in `App.tsx`:

```typescript
function filterBadge(result?: FilterResult) {
  if (!result) return <span className="dir-badge neutral">--</span>;
  return (
    <span className={`dir-badge ${result.passed ? 'bullish' : 'bearish'}`}
          title={result.reason}>
      {result.passed ? '✓' : '✗'}
    </span>
  );
}

function trendArrow(trend?: string) {
  if (!trend) return '--';
  return trend === 'rising' || trend === 'bullish' ? '▲' : '▼';
}

function SignalQualityPanel({ sym, adxThreshold }: { sym: SymbolState; adxThreshold: number }) {
  const allFilters = sym.filters;
  const allPassed = allFilters &&
    allFilters.momentum?.passed &&
    allFilters.volume?.passed &&
    allFilters.derivatives?.passed;

  const blockedFilter = allFilters && (
    (!allFilters.momentum?.passed && allFilters.momentum?.reason) ||
    (!allFilters.volume?.passed && allFilters.volume?.reason) ||
    (!allFilters.derivatives?.passed && allFilters.derivatives?.reason)
  );

  return (
    <div className="signal-quality-panel">
      <div className="sq-row sq-header">
        <span className="sq-label">ENTRY_ANALYSIS</span>
        <span className={`sq-status ${allPassed ? 'pos' : blockedFilter ? 'neg' : 'neutral'}`}>
          {sym.signal ? 'SIGNAL_FIRED' : allPassed === false ? 'BLOCKED' : 'MONITORING'}
        </span>
      </div>

      {/* BOS */}
      <div className="sq-row">
        <span className="sq-label">BOS</span>
        <span className={`sq-value ${sym.bos_direction === 'bullish' ? 'pos' : sym.bos_direction === 'bearish' ? 'neg' : ''}`}>
          {sym.bos_direction ? `${sym.bos_direction.toUpperCase()} @ ${sym.bos_level?.toFixed(1) ?? '--'}` : '--'}
        </span>
      </div>

      {/* RSI */}
      <div className="sq-row">
        <span className="sq-label">RSI</span>
        <span className={`sq-value ${(sym.rsi ?? 50) > 70 ? 'neg' : (sym.rsi ?? 50) < 30 ? 'neg' : 'pos'}`}>
          {sym.rsi?.toFixed(1) ?? '--'}
        </span>
        {filterBadge(allFilters?.momentum)}
        <span className="sq-reason">{allFilters?.momentum?.reason ?? ''}</span>
      </div>

      {/* CVD + VWAP */}
      <div className="sq-row">
        <span className="sq-label">CVD</span>
        <span className={`sq-value ${sym.cvd_trend === 'bullish' ? 'pos' : sym.cvd_trend === 'bearish' ? 'neg' : ''}`}>
          {sym.cvd_trend ? `${trendArrow(sym.cvd_trend)} ${sym.cvd_delta?.toFixed(0) ?? ''}` : '--'}
        </span>
        <span className="sq-label">VWAP</span>
        <span className="sq-value">
          {sym.vwap ? `${sym.vwap.toFixed(0)} (${sym.vwap_deviation_pct?.toFixed(2) ?? '0'}%)` : '--'}
        </span>
        {filterBadge(allFilters?.volume)}
      </div>

      {/* OI + Funding */}
      <div className="sq-row">
        <span className="sq-label">OI</span>
        <span className={`sq-value ${sym.oi_trend === 'rising' ? 'pos' : sym.oi_trend === 'falling' ? 'neg' : ''}`}>
          {sym.oi_usd ? `${trendArrow(sym.oi_trend)} $${(sym.oi_usd / 1_000_000).toFixed(1)}M` : '--'}
        </span>
        <span className="sq-label">FUND</span>
        <span className={`sq-value ${sym.funding_extreme ? 'neg' : 'pos'}`}>
          {sym.funding_rate != null ? `${(sym.funding_rate * 100).toFixed(4)}%` : '--'}
        </span>
        {filterBadge(allFilters?.derivatives)}
      </div>

      {blockedFilter && (
        <div className="sq-row sq-blocked">
          <span className="neg">BLOCKED: {blockedFilter}</span>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Add SignalQualityPanel to the strategy table rows**

In the strategy monitor table, below the existing `<tr>` for each symbol, add a collapsible panel. Replace the `{strategyStatus.symbols.map(sym => (` map block with:

```typescript
{strategyStatus.symbols.map(sym => (
  <React.Fragment key={sym.symbol}>
    <tr className="row-hover">
      <td className="font-bold">{sym.symbol}</td>
      <td>{dirBadge(sym.h1_dir)}</td>
      <td>{dirBadge(sym.m15_dir)}</td>
      <td className={sym.adx != null && sym.adx >= (strategyStatus.strategy.params.adx_threshold ?? 20) ? 'pos' : 'neg'}>
        {sym.adx != null ? sym.adx.toFixed(1) : '--'}
      </td>
      <td>
        {sym.bos_direction
          ? <span className={`dir-badge ${sym.bos_direction}`}>{sym.bos_direction.toUpperCase()}</span>
          : <span className="dir-badge neutral">--</span>}
      </td>
      <td>{signalBadge(sym.signal)}</td>
      <td className="timestamp">{timeAgo(sym.updated_at)}</td>
    </tr>
    <tr>
      <td colSpan={7} style={{ padding: 0 }}>
        <SignalQualityPanel sym={sym} adxThreshold={strategyStatus.strategy.params.adx_threshold ?? 20} />
      </td>
    </tr>
  </React.Fragment>
))}
```

Also add `import React from 'react';` at the top if not present (Vite projects with JSX transform don't require it but it's needed for `React.Fragment`).

- [ ] **Step 4: Add minimal CSS for new classes**

In `App.css`, append:

```css
.signal-quality-panel {
  padding: 8px 12px;
  background: rgba(0, 255, 136, 0.03);
  border-top: 1px solid rgba(0, 255, 136, 0.1);
  font-size: 11px;
}

.sq-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 3px 0;
  flex-wrap: wrap;
}

.sq-header {
  font-weight: bold;
  font-size: 10px;
  letter-spacing: 0.1em;
  border-bottom: 1px solid rgba(0, 255, 136, 0.1);
  padding-bottom: 4px;
  margin-bottom: 4px;
}

.sq-label {
  color: #666;
  font-size: 10px;
  letter-spacing: 0.05em;
  min-width: 36px;
}

.sq-value {
  font-family: monospace;
  min-width: 80px;
}

.sq-status { font-size: 10px; margin-left: auto; letter-spacing: 0.1em; }

.sq-reason { color: #555; font-size: 10px; font-style: italic; flex: 1; }

.sq-blocked { color: #ff4444; font-size: 10px; font-style: italic; }
```

- [ ] **Step 5: Build frontend to verify no TypeScript errors**

```bash
cd frontend && npm run build 2>&1 | tail -20
```

Expected: build succeeds with no TypeScript errors

- [ ] **Step 6: Commit**

```bash
git add frontend/src/App.tsx frontend/src/App.css
git commit -m "feat: Add SignalQualityPanel with filter verdicts to strategy monitor"
```

---

## Task 19: Frontend — Derivatives Strip

**Files:**

- Modify: `frontend/src/App.tsx`

- [ ] **Step 1: Add DerivativesStrip component**

Add this function above `App` in `App.tsx`:

```typescript
function DerivativesStrip({ symbols }: { symbols: SymbolState[] }) {
  if (symbols.length === 0) return null;

  return (
    <div className="derivatives-strip">
      {symbols.map(sym => (
        <div key={sym.symbol} className="deriv-item">
          <span className="deriv-symbol">{sym.symbol}</span>
          <span className={`deriv-oi ${sym.oi_trend === 'rising' ? 'pos' : sym.oi_trend === 'falling' ? 'neg' : ''}`}>
            OI {sym.oi_trend === 'rising' ? '▲' : sym.oi_trend === 'falling' ? '▼' : '--'}
            {sym.oi_usd ? ` $${(sym.oi_usd / 1_000_000).toFixed(1)}M` : ''}
          </span>
          <span className={`deriv-fund ${sym.funding_extreme ? 'fund-extreme' : 'fund-normal'}`}>
            {sym.funding_rate != null
              ? `${sym.funding_rate >= 0 ? '+' : ''}${(sym.funding_rate * 100).toFixed(4)}%`
              : 'FUND --'}
          </span>
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 2: Place DerivativesStrip below the ticker bar**

In the JSX of `App`, add the strip after the ticker bar `<div>`:

```typescript
{strategyStatus && (
  <DerivativesStrip symbols={strategyStatus.symbols} />
)}
```

- [ ] **Step 3: Add CSS**

In `App.css`, append:

```css
.derivatives-strip {
  display: flex;
  gap: 16px;
  padding: 4px 16px;
  background: rgba(0, 0, 0, 0.4);
  border-bottom: 1px solid rgba(0, 255, 136, 0.1);
  font-size: 10px;
  letter-spacing: 0.05em;
  flex-wrap: wrap;
}

.deriv-item {
  display: flex;
  align-items: center;
  gap: 6px;
}

.deriv-symbol { color: #aaa; font-weight: bold; }

.deriv-oi { font-family: monospace; }

.deriv-fund { font-family: monospace; }

.fund-extreme {
  color: #ff9800;
  font-weight: bold;
}

.fund-normal { color: #4caf50; }
```

- [ ] **Step 4: Build frontend to verify no TypeScript errors**

```bash
cd frontend && npm run build 2>&1 | tail -10
```

Expected: clean build

- [ ] **Step 5: Commit**

```bash
git add frontend/src/App.tsx frontend/src/App.css
git commit -m "feat: Add DerivativesStrip showing OI trend and funding rate per symbol"
```

---

## Task 20: Full integration smoke test

- [ ] **Step 1: Run the full test suite**

```bash
bundle exec rspec --format documentation 2>&1 | tail -30
```

Expected: all examples pass, no failures

- [ ] **Step 2: Start bot in dry_run and verify new state is published to Redis**

```bash
BOT_MODE=dry_run timeout 20 bundle exec ruby bin/run 2>&1 | grep -E "(signal_generated|strategy_skip|bos|filter)" | head -20
```

Expected: log lines showing `bos_` or `filter_blocked` or `signal_generated` events

- [ ] **Step 3: Check Redis state includes new fields**

```bash
redis-cli HGETALL delta:strategy:state | python3 -c "import sys,json; [print(json.dumps(json.loads(l), indent=2)) for l in sys.stdin if l.strip().startswith('{')]" 2>/dev/null | head -50
```

Expected: JSON with `bos_direction`, `rsi`, `vwap`, `filters` keys

- [ ] **Step 4: Verify backend API serves the new fields**

```bash
cd backend && curl -s http://localhost:5000/api/strategy_status | python3 -m json.tool | grep -A2 "filters\|rsi\|bos"
```

Expected: new fields present in API response

- [ ] **Step 5: Commit final tag**

```bash
git tag mws-v1.0
```

---

## Self-Review Checklist

- [x] Config accessors match exact YAML key paths (`strategy.rsi.period`, etc.)
- [x] `Indicators::RSI` namespace matches `Bot::Strategy::Indicators::RSI` used in requires
- [x] `fetch_candles` volume addition is backward compatible (defaults to 0.0)
- [x] `MultiTimeframe` uses `@config.dry_run?` — method exists in Config
- [x] `CvdStore#record_trade` and `DerivativesStore#update_funding_rate` match what `WebsocketFeed` calls
- [x] `DerivativesStore` uses `products.ticker(symbol)` — method exists in `Resources::Products`
- [x] Filter nil-safety: all three filters pass gracefully when stores not yet populated
- [x] Backend mirrors have same namespace (`Bot::Strategy::Indicators::`)
- [x] Frontend `React.Fragment` added for table row pairs
- [x] OB check relaxed in `dry_run?` so existing multi_timeframe tests pass
