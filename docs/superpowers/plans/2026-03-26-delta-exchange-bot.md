# Delta Exchange Futures Trading Bot Implementation Plan

> **Repo status (2026-04):** Superseded as an implementation target. The **canonical** runtime is the Rails app under **`backend/`** (`Trading::Runner`, Solid Queue, etc.). See root **`README.md`**, **`backend/README.md`**, and **`backend/docs/architecture_diagrams.md`**. This file is kept for historical planning context.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Ruby automated futures trading bot for Delta Exchange India that trades multiple crypto perpetuals using a multi-timeframe Supertrend + ADX strategy with percentage-based trailing stop exits.

**Architecture:** Multi-threaded standalone Ruby app — WebSocket thread streams live LTP into a Mutex-protected PriceStore; a Strategy thread fetches OHLCV via REST every 5 minutes, evaluates MTF confluence signals, and places orders; a Trailing Stop thread polls PriceStore every 15 seconds and triggers exits. A Supervisor manages all thread lifecycles with exponential backoff restart and a circuit breaker.

**Tech Stack:** Ruby 3.2+, delta_exchange gem (local, path: `../delta_exchange`), dotenv, telegram-bot-ruby, tzinfo, rspec

---

## File Map

| File                                         | Responsibility                                                                                                |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `bin/run`                                    | Entry point — loads env, boots Config, builds all components, starts Supervisor                               |
| `config/bot.yml`                             | All runtime configuration with sensible defaults                                                              |
| `.env.example`                               | Template for API keys and credentials                                                                         |
| `Gemfile`                                    | Dependencies                                                                                                  |
| `lib/bot/config.rb`                          | Loads `bot.yml`, validates all fields, exposes typed accessors                                                |
| `lib/bot/product_cache.rb`                   | Fetches products at startup, builds forward+inverse symbol↔product_id maps                                    |
| `lib/bot/supervisor.rb`                      | Spawns and monitors threads, exponential backoff restart, circuit breaker, graceful shutdown                  |
| `lib/bot/feed/price_store.rb`                | Mutex-protected hash of `symbol → ltp`; written by WebSocket thread, read by trailing stop thread             |
| `lib/bot/feed/websocket_feed.rb`             | Wraps `DeltaExchange::Websocket::Client`, subscribes to `v2/ticker`, updates PriceStore                       |
| `lib/bot/strategy/supertrend.rb`             | Pure function: array of OHLCV hashes → array of `{direction:, line:}` using Wilder's ATR + band carry-forward |
| `lib/bot/strategy/adx.rb`                    | Pure function: array of OHLCV hashes → array of `{adx:, plus_di:, minus_di:}` using Wilder's smoothing        |
| `lib/bot/strategy/signal.rb`                 | Value object: `symbol, side, entry_price, candle_ts`                                                          |
| `lib/bot/strategy/multi_timeframe.rb`        | Fetches OHLCV for 3 timeframes, runs indicators, checks MTF confluence, returns Signal or nil                 |
| `lib/bot/execution/risk_calculator.rb`       | Pure function: capital + config + entry_price → `final_lots` integer, with margin cap guard                   |
| `lib/bot/execution/position_tracker.rb`      | Mutex-protected open position state per symbol: entry, side, peak, stop, lots, entry_time                     |
| `lib/bot/execution/order_manager.rb`         | Places/simulates orders via delta_exchange gem; updates PositionTracker on fill                               |
| `lib/bot/account/capital_manager.rb`         | Fetches `WalletBalance.find_by_asset('USDT').available_balance`, converts to INR                              |
| `lib/bot/notifications/logger.rb`            | Writes JSON-line entries to `logs/bot.log`                                                                    |
| `lib/bot/notifications/telegram_notifier.rb` | Sends Telegram messages; no-ops gracefully if disabled                                                        |
| `lib/bot/runner.rb`                          | Wires all components together and delegates to Supervisor                                                     |

---

## Task 1: Project Scaffold — Gemfile, Config, and Env

**Files:**
- Create: `Gemfile`
- Create: `config/bot.yml`
- Create: `.env.example`
- Create: `lib/bot/config.rb`
- Create: `spec/spec_helper.rb`
- Create: `spec/bot/config_spec.rb`

- [ ] **Step 1: Create Gemfile**

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 3.2.0"

gem "delta_exchange", path: "../delta_exchange"
gem "dotenv"
gem "telegram-bot-ruby"
gem "tzinfo"

group :test do
  gem "rspec"
  gem "rspec-mocks"
end
```

- [ ] **Step 2: Run `bundle install`**

```bash
bundle install
```

Expected: Gemfile.lock created, no errors.

- [ ] **Step 3: Create `config/bot.yml`**

```yaml
mode: testnet  # dry_run | testnet | live

strategy:
  supertrend:
    atr_period: 10
    multiplier: 3.0
  adx:
    period: 14
    threshold: 25
  trailing_stop_pct: 1.5
  timeframes:
    trend: "60"
    confirm: "15"
    entry: "5"
  candles_lookback: 100
  min_candles_required: 30

risk:
  risk_per_trade_pct: 1.5
  max_concurrent_positions: 5
  max_margin_per_position_pct: 40
  usd_to_inr_rate: 85.0

symbols:
  - symbol: BTCUSD
    leverage: 10
  - symbol: ETHUSD
    leverage: 15
  - symbol: SOLUSD
    leverage: 20

notifications:
  telegram:
    enabled: false
    bot_token: ""
    chat_id: ""
  daily_summary_time: "18:00"

logging:
  level: info
  file: logs/bot.log
```

- [ ] **Step 4: Create `.env.example`**

```bash
DELTA_API_KEY=your_api_key_here
DELTA_API_SECRET=your_api_secret_here
TELEGRAM_BOT_TOKEN=your_telegram_bot_token
TELEGRAM_CHAT_ID=your_chat_id
TZ=Asia/Kolkata
BOT_MODE=
```

- [ ] **Step 5: Create `spec/spec_helper.rb`**

```ruby
# frozen_string_literal: true

require "bundler/setup"
require "dotenv"
Dotenv.load(".env.test") if File.exist?(".env.test")

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with :rspec
  config.order = :random
end
```

- [ ] **Step 6: Write failing tests for Config**

Create `spec/bot/config_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/config"

RSpec.describe Bot::Config do
  let(:valid_yaml) do
    {
      "mode" => "testnet",
      "strategy" => {
        "supertrend" => { "atr_period" => 10, "multiplier" => 3.0 },
        "adx" => { "period" => 14, "threshold" => 25 },
        "trailing_stop_pct" => 1.5,
        "timeframes" => { "trend" => "60", "confirm" => "15", "entry" => "5" },
        "candles_lookback" => 100,
        "min_candles_required" => 30
      },
      "risk" => {
        "risk_per_trade_pct" => 1.5,
        "max_concurrent_positions" => 5,
        "max_margin_per_position_pct" => 40,
        "usd_to_inr_rate" => 85.0
      },
      "symbols" => [
        { "symbol" => "BTCUSD", "leverage" => 10 }
      ],
      "notifications" => {
        "telegram" => { "enabled" => false, "bot_token" => "", "chat_id" => "" },
        "daily_summary_time" => "18:00"
      },
      "logging" => { "level" => "info", "file" => "logs/bot.log" }
    }
  end

  subject(:config) { described_class.new(valid_yaml) }

  it "exposes mode" do
    expect(config.mode).to eq("testnet")
  end

  it "exposes symbols with leverage" do
    expect(config.symbols).to eq([{ symbol: "BTCUSD", leverage: 10 }])
  end

  it "exposes supertrend config" do
    expect(config.supertrend_atr_period).to eq(10)
    expect(config.supertrend_multiplier).to eq(3.0)
  end

  it "exposes adx config" do
    expect(config.adx_period).to eq(14)
    expect(config.adx_threshold).to eq(25)
  end

  it "exposes risk config" do
    expect(config.risk_per_trade_pct).to eq(1.5)
    expect(config.max_concurrent_positions).to eq(5)
    expect(config.usd_to_inr_rate).to eq(85.0)
  end

  it "exposes timeframes" do
    expect(config.timeframe_trend).to eq("60")
    expect(config.timeframe_confirm).to eq("15")
    expect(config.timeframe_entry).to eq("5")
  end

  it "exposes leverage for a symbol" do
    expect(config.leverage_for("BTCUSD")).to eq(10)
  end

  context "with invalid mode" do
    it "raises on invalid mode" do
      bad = valid_yaml.merge("mode" => "invalid")
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /mode/)
    end
  end

  context "with out-of-range risk_per_trade_pct" do
    it "raises when > 10" do
      bad = valid_yaml.dup
      bad["risk"] = valid_yaml["risk"].merge("risk_per_trade_pct" => 15)
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /risk_per_trade_pct/)
    end
  end

  context "with empty symbols" do
    it "raises on empty symbols list" do
      bad = valid_yaml.merge("symbols" => [])
      expect { described_class.new(bad) }.to raise_error(Bot::Config::ValidationError, /symbols/)
    end
  end
end
```

- [ ] **Step 7: Run tests to confirm they fail**

```bash
bundle exec rspec spec/bot/config_spec.rb
```

Expected: `LoadError` — `bot/config` not found.

- [ ] **Step 8: Implement `lib/bot/config.rb`**

```ruby
# frozen_string_literal: true

require "yaml"

module Bot
  class Config
    class ValidationError < StandardError; end

    VALID_MODES = %w[dry_run testnet live].freeze

    def initialize(raw)
      @raw = raw
      validate!
    end

    def self.load(path = File.expand_path("../../config/bot.yml", __dir__))
      raw = YAML.safe_load(File.read(path), permitted_classes: [], aliases: true)
      mode_override = ENV["BOT_MODE"]
      raw["mode"] = mode_override if mode_override && !mode_override.empty?
      new(raw)
    end

    def mode               = @raw.fetch("mode")
    def dry_run?           = mode == "dry_run"
    def testnet?           = mode == "testnet"
    def live?              = mode == "live"

    def symbols
      @raw["symbols"].map { |s| { symbol: s["symbol"], leverage: s["leverage"] } }
    end

    def symbol_names       = symbols.map { |s| s[:symbol] }

    def leverage_for(symbol)
      entry = symbols.find { |s| s[:symbol] == symbol }
      raise ArgumentError, "Unknown symbol: #{symbol}" unless entry
      entry[:leverage]
    end

    def supertrend_atr_period  = @raw.dig("strategy", "supertrend", "atr_period").to_i
    def supertrend_multiplier  = @raw.dig("strategy", "supertrend", "multiplier").to_f
    def adx_period             = @raw.dig("strategy", "adx", "period").to_i
    def adx_threshold          = @raw.dig("strategy", "adx", "threshold").to_f
    def trailing_stop_pct      = @raw.dig("strategy", "trailing_stop_pct").to_f
    def timeframe_trend        = @raw.dig("strategy", "timeframes", "trend")
    def timeframe_confirm      = @raw.dig("strategy", "timeframes", "confirm")
    def timeframe_entry        = @raw.dig("strategy", "timeframes", "entry")
    def candles_lookback       = @raw.dig("strategy", "candles_lookback").to_i
    def min_candles_required   = @raw.dig("strategy", "min_candles_required").to_i

    def risk_per_trade_pct           = @raw.dig("risk", "risk_per_trade_pct").to_f
    def max_concurrent_positions     = @raw.dig("risk", "max_concurrent_positions").to_i
    def max_margin_per_position_pct  = @raw.dig("risk", "max_margin_per_position_pct").to_f
    def usd_to_inr_rate              = @raw.dig("risk", "usd_to_inr_rate").to_f

    def telegram_enabled?  = @raw.dig("notifications", "telegram", "enabled") == true
    def telegram_token     = @raw.dig("notifications", "telegram", "bot_token")
    def telegram_chat_id   = @raw.dig("notifications", "telegram", "chat_id").to_s
    def daily_summary_time = @raw.dig("notifications", "daily_summary_time")

    def log_level  = @raw.dig("logging", "level") || "info"
    def log_file   = @raw.dig("logging", "file") || "logs/bot.log"

    private

    def validate!
      error("mode must be one of: #{VALID_MODES.join(', ')}") unless VALID_MODES.include?(mode)
      error("symbols must not be empty") if symbols.empty?
      error("risk_per_trade_pct must be between 0.1 and 10") unless risk_per_trade_pct.between?(0.1, 10.0)
      error("max_concurrent_positions must be 1–20") unless max_concurrent_positions.between?(1, 20)
      error("trailing_stop_pct must be 0.1–20") unless trailing_stop_pct.between?(0.1, 20.0)
      error("supertrend.atr_period must be 1–50") unless supertrend_atr_period.between?(1, 50)
      error("supertrend.multiplier must be 0.5–10") unless supertrend_multiplier.between?(0.5, 10.0)
      error("adx.period must be 1–50") unless adx_period.between?(1, 50)
      error("adx.threshold must be 10–50") unless adx_threshold.between?(10, 50)
      error("usd_to_inr_rate must be > 0") unless usd_to_inr_rate.positive?
      symbols.each do |s|
        error("leverage for #{s[:symbol]} must be 1–200") unless s[:leverage].between?(1, 200)
      end
    end

    def error(msg)
      raise ValidationError, "Config error: #{msg}"
    end
  end
end
```

- [ ] **Step 9: Run tests to confirm they pass**

```bash
bundle exec rspec spec/bot/config_spec.rb
```

Expected: All green.

- [ ] **Step 10: Commit**

```bash
git add Gemfile Gemfile.lock config/bot.yml .env.example spec/spec_helper.rb spec/bot/config_spec.rb lib/bot/config.rb
git commit -m "feat: project scaffold with Config and validation"
```

---

## Task 2: Logger and Telegram Notifier

**Files:**
- Create: `lib/bot/notifications/logger.rb`
- Create: `lib/bot/notifications/telegram_notifier.rb`
- Create: `spec/bot/notifications/logger_spec.rb`
- Create: `spec/bot/notifications/telegram_notifier_spec.rb`
- Create: `logs/.gitkeep`

- [ ] **Step 1: Write failing tests for Logger**

Create `spec/bot/notifications/logger_spec.rb`:

```ruby
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
    expect(File.exist?(log_file)).to be(false).or(satisfy { File.read(log_file).strip.empty? })
  end

  it "writes error entries regardless of level" do
    logger.error("crash", message: "boom")
    entry = JSON.parse(File.readlines(log_file).last)
    expect(entry["level"]).to eq("error")
  end
end
```

- [ ] **Step 2: Write failing tests for TelegramNotifier**

Create `spec/bot/notifications/telegram_notifier_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/notifications/telegram_notifier"

RSpec.describe Bot::Notifications::TelegramNotifier do
  context "when disabled" do
    subject(:notifier) { described_class.new(enabled: false, token: "", chat_id: "") }

    it "does not raise and returns nil when sending" do
      expect { notifier.send_message("hello") }.not_to raise_error
    end
  end

  context "when enabled" do
    let(:bot_double) { instance_double("Telegram::Bot::Client") }
    subject(:notifier) { described_class.new(enabled: true, token: "token", chat_id: "123") }

    before do
      allow(notifier).to receive(:client).and_return(bot_double)
      allow(bot_double).to receive(:api).and_return(double(send_message: true))
    end

    it "calls the Telegram API" do
      expect(bot_double.api).to receive(:send_message).with(chat_id: "123", text: "hello", parse_mode: "HTML")
      notifier.send_message("hello")
    end
  end
end
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
bundle exec rspec spec/bot/notifications/
```

Expected: `LoadError`.

- [ ] **Step 4: Implement `lib/bot/notifications/logger.rb`**

```ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Bot
  module Notifications
    class Logger
      LEVELS = %w[debug info warn error].freeze

      def initialize(file:, level: "info")
        @file = file
        @min_level = LEVELS.index(level.to_s) || 1
        FileUtils.mkdir_p(File.dirname(@file))
      end

      def debug(event, **payload) = log("debug", event, payload)
      def info(event, **payload)  = log("info",  event, payload)
      def warn(event, **payload)  = log("warn",  event, payload)
      def error(event, **payload) = log("error", event, payload)

      private

      def log(level, event, payload)
        return if LEVELS.index(level) < @min_level

        entry = { ts: Time.now.utc.iso8601, level: level, event: event }.merge(payload)
        File.open(@file, "a") { |f| f.puts(entry.to_json) }
      end
    end
  end
end
```

- [ ] **Step 5: Implement `lib/bot/notifications/telegram_notifier.rb`**

```ruby
# frozen_string_literal: true

require "telegram/bot"

module Bot
  module Notifications
    class TelegramNotifier
      def initialize(enabled:, token:, chat_id:)
        @enabled = enabled
        @token   = token
        @chat_id = chat_id.to_s
      end

      def send_message(text)
        return unless @enabled && !@token.to_s.empty?

        client.api.send_message(chat_id: @chat_id, text: text, parse_mode: "HTML")
      rescue StandardError => e
        warn "[TelegramNotifier] Failed to send: #{e.message}"
      end

      private

      def client
        @client ||= Telegram::Bot::Client.new(@token)
      end
    end
  end
end
```

- [ ] **Step 6: Create `logs/.gitkeep`**

```bash
mkdir -p logs && touch logs/.gitkeep
```

- [ ] **Step 7: Run tests**

```bash
bundle exec rspec spec/bot/notifications/
```

Expected: All green.

- [ ] **Step 8: Commit**

```bash
git add lib/bot/notifications/ spec/bot/notifications/ logs/.gitkeep
git commit -m "feat: add Logger (JSON lines) and TelegramNotifier"
```

---

## Task 3: PriceStore and WebSocket Feed

**Files:**
- Create: `lib/bot/feed/price_store.rb`
- Create: `lib/bot/feed/websocket_feed.rb`
- Create: `spec/bot/feed/price_store_spec.rb`

- [ ] **Step 1: Write failing tests for PriceStore**

Create `spec/bot/feed/price_store_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/feed/price_store"

RSpec.describe Bot::Feed::PriceStore do
  subject(:store) { described_class.new }

  it "returns nil for unknown symbol" do
    expect(store.get("BTCUSD")).to be_nil
  end

  it "stores and retrieves LTP" do
    store.update("BTCUSD", 45_000.0)
    expect(store.get("BTCUSD")).to eq(45_000.0)
  end

  it "overwrites with latest value" do
    store.update("BTCUSD", 45_000.0)
    store.update("BTCUSD", 46_000.0)
    expect(store.get("BTCUSD")).to eq(46_000.0)
  end

  it "is thread-safe under concurrent writes" do
    threads = 10.times.map do |i|
      Thread.new { store.update("ETHUSD", i * 100.0) }
    end
    threads.each(&:join)
    expect(store.get("ETHUSD")).not_to be_nil
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/bot/feed/price_store_spec.rb
```

Expected: `LoadError`.

- [ ] **Step 3: Implement `lib/bot/feed/price_store.rb`**

```ruby
# frozen_string_literal: true

module Bot
  module Feed
    class PriceStore
      def initialize
        @prices = {}
        @mutex  = Mutex.new
      end

      def update(symbol, price)
        @mutex.synchronize { @prices[symbol] = price.to_f }
      end

      def get(symbol)
        @mutex.synchronize { @prices[symbol] }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/bot/feed/price_store_spec.rb
```

Expected: All green.

- [ ] **Step 5: Implement `lib/bot/feed/websocket_feed.rb`**

```ruby
# frozen_string_literal: true

require "delta_exchange"

module Bot
  module Feed
    class WebsocketFeed
      def initialize(symbols:, price_store:, logger:, testnet: false)
        @symbols     = symbols
        @price_store = price_store
        @logger      = logger
        @testnet     = testnet
        @client      = nil
      end

      def start
        @client = DeltaExchange::Websocket::Client.new(testnet: @testnet)

        @client.on(:open) do
          @logger.info("ws_connected")
          @client.subscribe([{ name: "v2/ticker", symbols: @symbols }])
        end

        @client.on(:message) do |data|
          next unless data.is_a?(Hash) && data["type"] == "v2/ticker"

          symbol = data["symbol"]
          price  = data["mark_price"]&.to_f || data["close"]&.to_f
          next unless symbol && price && price.positive?

          @price_store.update(symbol, price)
          @logger.debug("ltp_update", symbol: symbol, price: price)
        end

        @client.on(:close) do
          @logger.warn("ws_disconnected")
        end

        @client.on(:error) do |err|
          @logger.error("ws_error", message: err.to_s)
        end

        @client.connect!
      end

      def stop
        @client&.close
      end
    end
  end
end
```

- [ ] **Step 6: Commit**

```bash
git add lib/bot/feed/ spec/bot/feed/price_store_spec.rb
git commit -m "feat: add PriceStore (thread-safe) and WebsocketFeed"
```

---

## Task 4: Supertrend Indicator

**Files:**
- Create: `lib/bot/strategy/supertrend.rb`
- Create: `spec/bot/strategy/supertrend_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/supertrend_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/supertrend"

RSpec.describe Bot::Strategy::Supertrend do
  # 15 synthetic bars: trending up then reversing
  let(:candles) do
    prices = [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 109, 107, 104, 100]
    prices.map.with_index do |c, i|
      { open: c - 0.5, high: c + 1.0, low: c - 1.0, close: c.to_f }
    end
  end

  subject(:result) { described_class.compute(candles, atr_period: 3, multiplier: 1.5) }

  it "returns one result per candle" do
    expect(result.size).to eq(candles.size)
  end

  it "returns hash with :direction and :line keys" do
    expect(result.last).to include(:direction, :line)
  end

  it "reports bullish direction during uptrend" do
    expect(result[5][:direction]).to eq(:bullish)
  end

  it "flips to bearish after a significant drop" do
    expect(result.last[:direction]).to eq(:bearish)
  end

  it "returns nil for bars before enough data" do
    expect(result.first[:direction]).to be_nil
  end

  it "raises ArgumentError with fewer than 2 candles" do
    expect { described_class.compute([candles.first], atr_period: 3, multiplier: 1.5) }
      .to raise_error(ArgumentError)
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/bot/strategy/supertrend_spec.rb
```

Expected: `LoadError`.

- [ ] **Step 3: Implement `lib/bot/strategy/supertrend.rb`**

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module Supertrend
      def self.compute(candles, atr_period:, multiplier:)
        raise ArgumentError, "Need at least 2 candles" if candles.size < 2

        n       = candles.size
        results = Array.new(n) { { direction: nil, line: nil } }

        atr     = Array.new(n, 0.0)
        upper   = Array.new(n, 0.0)
        lower   = Array.new(n, 0.0)
        dir     = Array.new(n, :bullish)

        # First bar — seed ATR
        atr[0] = candles[0][:high].to_f - candles[0][:low].to_f

        (1...n).each do |i|
          c  = candles[i]
          cp = candles[i - 1]

          tr = [
            c[:high].to_f  - c[:low].to_f,
            (c[:high].to_f  - cp[:close].to_f).abs,
            (c[:low].to_f   - cp[:close].to_f).abs
          ].max

          # Wilder's smoothing
          atr[i] = (atr[i - 1] * (atr_period - 1) + tr) / atr_period

          hl2 = (c[:high].to_f + c[:low].to_f) / 2.0

          basic_upper = hl2 + multiplier * atr[i]
          basic_lower = hl2 - multiplier * atr[i]

          # Band carry-forward
          upper[i] = if basic_upper < upper[i - 1] || cp[:close].to_f > upper[i - 1]
                       basic_upper
                     else
                       upper[i - 1]
                     end

          lower[i] = if basic_lower > lower[i - 1] || cp[:close].to_f < lower[i - 1]
                       basic_lower
                     else
                       lower[i - 1]
                     end

          close = c[:close].to_f

          dir[i] = if dir[i - 1] == :bearish && close > upper[i - 1]
                     :bullish
                   elsif dir[i - 1] == :bullish && close < lower[i - 1]
                     :bearish
                   else
                     dir[i - 1]
                   end

          next if i < atr_period

          results[i] = {
            direction: dir[i],
            line: dir[i] == :bullish ? lower[i] : upper[i]
          }
        end

        results
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/bot/strategy/supertrend_spec.rb
```

Expected: All green.

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/supertrend.rb spec/bot/strategy/supertrend_spec.rb
git commit -m "feat: add Supertrend indicator with Wilder ATR and band carry-forward"
```

---

## Task 5: ADX Indicator

**Files:**
- Create: `lib/bot/strategy/adx.rb`
- Create: `spec/bot/strategy/adx_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/adx_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/adx"

RSpec.describe Bot::Strategy::ADX do
  # 40 candles: strong uptrend for first 20, then ranging
  let(:trending_candles) do
    (0...40).map do |i|
      base = 100.0 + (i < 20 ? i * 2 : 40.0)
      { high: base + 2.0, low: base - 2.0, close: base + 0.5 }
    end
  end

  subject(:result) { described_class.compute(trending_candles, period: 14) }

  it "returns one result per candle" do
    expect(result.size).to eq(trending_candles.size)
  end

  it "returns hash with :adx, :plus_di, :minus_di" do
    expect(result.last).to include(:adx, :plus_di, :minus_di)
  end

  it "returns nil for bars before enough data" do
    expect(result[0][:adx]).to be_nil
  end

  it "returns high ADX during strong trend" do
    # ADX should be > 25 during a strong uptrend after warmup
    adx_values = result[28..].map { |r| r[:adx] }.compact
    expect(adx_values.any? { |v| v > 20 }).to be(true)
  end

  it "returns plus_di > minus_di during uptrend" do
    valid = result.select { |r| r[:adx] }
    uptrend_bars = valid.first(10)
    expect(uptrend_bars.all? { |r| r[:plus_di] > r[:minus_di] }).to be(true)
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/bot/strategy/adx_spec.rb
```

Expected: `LoadError`.

- [ ] **Step 3: Implement `lib/bot/strategy/adx.rb`**

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    module ADX
      def self.compute(candles, period:)
        n       = candles.size
        results = Array.new(n) { { adx: nil, plus_di: nil, minus_di: nil } }

        return results if n < period * 2

        tr_arr      = Array.new(n, 0.0)
        plus_dm_arr = Array.new(n, 0.0)
        minus_dm_arr = Array.new(n, 0.0)

        (1...n).each do |i|
          c  = candles[i]
          cp = candles[i - 1]

          up_move   = c[:high].to_f - cp[:high].to_f
          down_move = cp[:low].to_f  - c[:low].to_f

          plus_dm_arr[i]  = up_move > down_move && up_move > 0 ? up_move : 0.0
          minus_dm_arr[i] = down_move > up_move && down_move > 0 ? down_move : 0.0

          tr_arr[i] = [
            c[:high].to_f - c[:low].to_f,
            (c[:high].to_f - cp[:close].to_f).abs,
            (c[:low].to_f  - cp[:close].to_f).abs
          ].max
        end

        # Seed Wilder smoothing with sum of first `period` values
        s_tr       = tr_arr[1..period].sum
        s_plus_dm  = plus_dm_arr[1..period].sum
        s_minus_dm = minus_dm_arr[1..period].sum

        dx_arr = []

        plus_di  = 100.0 * s_plus_dm  / s_tr
        minus_di = 100.0 * s_minus_dm / s_tr
        dx_arr << (100.0 * (plus_di - minus_di).abs / (plus_di + minus_di)) if (plus_di + minus_di).positive?

        ((period + 1)...n).each do |i|
          s_tr       = s_tr       - (s_tr       / period) + tr_arr[i]
          s_plus_dm  = s_plus_dm  - (s_plus_dm  / period) + plus_dm_arr[i]
          s_minus_dm = s_minus_dm - (s_minus_dm / period) + minus_dm_arr[i]

          plus_di  = 100.0 * s_plus_dm  / s_tr
          minus_di = 100.0 * s_minus_dm / s_tr

          dx = if (plus_di + minus_di).positive?
                 100.0 * (plus_di - minus_di).abs / (plus_di + minus_di)
               else
                 0.0
               end
          dx_arr << dx

          next if dx_arr.size < period

          adx = if dx_arr.size == period
                  dx_arr.sum / period
                else
                  (results[i - 1][:adx] * (period - 1) + dx) / period
                end

          results[i] = { adx: adx.round(4), plus_di: plus_di.round(4), minus_di: minus_di.round(4) }
        end

        results
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/bot/strategy/adx_spec.rb
```

Expected: All green.

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/adx.rb spec/bot/strategy/adx_spec.rb
git commit -m "feat: add ADX indicator with Wilder smoothing"
```

---

## Task 6: Signal Value Object and ProductCache

**Files:**
- Create: `lib/bot/strategy/signal.rb`
- Create: `lib/bot/product_cache.rb`
- Create: `spec/bot/product_cache_spec.rb`

- [ ] **Step 1: Implement `lib/bot/strategy/signal.rb`** (no test needed — simple value object)

```ruby
# frozen_string_literal: true

module Bot
  module Strategy
    Signal = Struct.new(:symbol, :side, :entry_price, :candle_ts, keyword_init: true) do
      def long?  = side == :long
      def short? = side == :short
    end
  end
end
```

- [ ] **Step 2: Write failing tests for ProductCache**

Create `spec/bot/product_cache_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/product_cache"

RSpec.describe Bot::ProductCache do
  let(:products) do
    [
      double("Product", id: 1, symbol: "BTCUSD", contract_value: 0.001),
      double("Product", id: 2, symbol: "ETHUSD", contract_value: 0.01)
    ]
  end

  subject(:cache) { described_class.new(symbols: %w[BTCUSD ETHUSD], products: products) }

  it "looks up product_id by symbol" do
    expect(cache.product_id_for("BTCUSD")).to eq(1)
  end

  it "looks up contract_value by symbol" do
    expect(cache.contract_value_for("BTCUSD")).to eq(0.001)
  end

  it "looks up symbol by product_id (inverse lookup)" do
    expect(cache.symbol_for(2)).to eq("ETHUSD")
  end

  it "raises if a configured symbol is not found in products" do
    expect {
      described_class.new(symbols: %w[BTCUSD UNKNOWN], products: products)
    }.to raise_error(Bot::ProductCache::MissingProductError, /UNKNOWN/)
  end
end
```

- [ ] **Step 3: Run to confirm failure**

```bash
bundle exec rspec spec/bot/product_cache_spec.rb
```

Expected: `LoadError`.

- [ ] **Step 4: Implement `lib/bot/product_cache.rb`**

```ruby
# frozen_string_literal: true

module Bot
  class ProductCache
    class MissingProductError < StandardError; end

    def initialize(symbols:, products:)
      @forward  = {}  # symbol → { product_id:, contract_value: }
      @inverse  = {}  # product_id → symbol

      symbols.each do |sym|
        product = products.find { |p| p.symbol == sym }
        raise MissingProductError, "Product not found for symbol: #{sym}" unless product

        @forward[sym] = { product_id: product.id, contract_value: product.contract_value.to_f }
        @inverse[product.id] = sym
      end
    end

    def product_id_for(symbol)    = @forward.fetch(symbol)[:product_id]
    def contract_value_for(symbol) = @forward.fetch(symbol)[:contract_value]
    def symbol_for(product_id)    = @inverse[product_id]
    def known_symbol?(symbol)     = @forward.key?(symbol)
  end
end
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/bot/product_cache_spec.rb
```

Expected: All green.

- [ ] **Step 6: Commit**

```bash
git add lib/bot/strategy/signal.rb lib/bot/product_cache.rb spec/bot/product_cache_spec.rb
git commit -m "feat: add Signal value object and ProductCache with forward+inverse indexes"
```

---

## Task 7: RiskCalculator

**Files:**
- Create: `lib/bot/execution/risk_calculator.rb`
- Create: `spec/bot/execution/risk_calculator_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/execution/risk_calculator_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/execution/risk_calculator"

RSpec.describe Bot::Execution::RiskCalculator do
  subject(:calculator) { described_class.new(usd_to_inr_rate: 85.0) }

  # BTCUSD: $45,000 entry, 10x leverage, 1.5% risk, 1.5% trail, 0.001 contract_value
  # available_usdt = 500
  # capital_inr = 42500, risk_inr = 637.5, risk_usd = 7.5
  # trail_distance = 675, loss_per_lot = 0.675
  # raw_lots = 11.11, leveraged_lots = 111.11, final_lots = 111
  # margin = 111 * 0.001 * 45000 / 10 = 499.5 → exceeds 40% cap (200)
  # capped_lots = floor(200 * 10 / (0.001 * 45000)) = floor(44.44) = 44

  let(:params) do
    {
      available_usdt: 500.0,
      entry_price_usd: 45_000.0,
      leverage: 10,
      risk_per_trade_pct: 1.5,
      trail_pct: 1.5,
      contract_value: 0.001,
      max_margin_per_position_pct: 40.0
    }
  end

  it "returns 44 lots after margin cap for BTCUSD example" do
    expect(calculator.compute(**params)).to eq(44)
  end

  it "returns 0 when capital is too small for even 1 lot" do
    expect(calculator.compute(**params.merge(available_usdt: 0.1))).to eq(0)
  end

  it "does not apply margin cap when position is within limit" do
    # Small position: 1 lot of a $1 contract at 1x = no cap needed
    result = calculator.compute(
      available_usdt: 10_000.0,
      entry_price_usd: 1.0,
      leverage: 1,
      risk_per_trade_pct: 1.5,
      trail_pct: 1.5,
      contract_value: 1.0,
      max_margin_per_position_pct: 40.0
    )
    expect(result).to be > 0
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/bot/execution/risk_calculator_spec.rb
```

Expected: `LoadError`.

- [ ] **Step 3: Implement `lib/bot/execution/risk_calculator.rb`**

```ruby
# frozen_string_literal: true

module Bot
  module Execution
    class RiskCalculator
      def initialize(usd_to_inr_rate:)
        @usd_to_inr_rate = usd_to_inr_rate
      end

      # Returns final_lots as Integer (0 means skip trade)
      def compute(available_usdt:, entry_price_usd:, leverage:, risk_per_trade_pct:,
                  trail_pct:, contract_value:, max_margin_per_position_pct:)
        capital_inr    = available_usdt * @usd_to_inr_rate
        risk_inr       = capital_inr * (risk_per_trade_pct / 100.0)
        risk_usd       = risk_inr / @usd_to_inr_rate

        trail_distance = entry_price_usd * (trail_pct / 100.0)
        loss_per_lot   = trail_distance * contract_value

        return 0 if loss_per_lot.zero?

        raw_lots       = risk_usd / loss_per_lot
        leveraged_lots = raw_lots * leverage
        final_lots     = leveraged_lots.floor

        return 0 if final_lots <= 0

        # Margin cap: (lots × contract_value × price) / leverage <= available × cap%
        max_margin_usd  = available_usdt * (max_margin_per_position_pct / 100.0)
        margin_per_lot  = (contract_value * entry_price_usd) / leverage

        if margin_per_lot.positive?
          max_lots_by_margin = (max_margin_usd / margin_per_lot).floor
          final_lots = [final_lots, max_lots_by_margin].min
        end

        [final_lots, 0].max
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/bot/execution/risk_calculator_spec.rb
```

Expected: All green.

- [ ] **Step 5: Commit**

```bash
git add lib/bot/execution/risk_calculator.rb spec/bot/execution/risk_calculator_spec.rb
git commit -m "feat: add RiskCalculator with lot sizing and margin cap guard"
```

---

## Task 8: PositionTracker

**Files:**
- Create: `lib/bot/execution/position_tracker.rb`
- Create: `spec/bot/execution/position_tracker_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/execution/position_tracker_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/execution/position_tracker"

RSpec.describe Bot::Execution::PositionTracker do
  subject(:tracker) { described_class.new }

  let(:position) do
    {
      symbol: "BTCUSD",
      side: :long,
      lots: 44,
      entry_price: 45_000.0,
      leverage: 10,
      trail_pct: 1.5,
      entry_time: Time.now.utc
    }
  end

  describe "#open" do
    it "records a new position" do
      tracker.open(position)
      expect(tracker.open?("BTCUSD")).to be(true)
    end

    it "sets peak_price and stop_price on open" do
      tracker.open(position)
      pos = tracker.get("BTCUSD")
      expect(pos[:peak_price]).to eq(45_000.0)
      expect(pos[:stop_price]).to eq(45_000.0 * (1 - 0.015))
    end
  end

  describe "#update_trailing_stop" do
    before { tracker.open(position) }

    it "raises peak and stop when price moves in favour (long)" do
      tracker.update_trailing_stop("BTCUSD", 46_000.0)
      pos = tracker.get("BTCUSD")
      expect(pos[:peak_price]).to eq(46_000.0)
      expect(pos[:stop_price]).to be_within(0.01).of(46_000.0 * 0.985)
    end

    it "does not lower peak when price drops (long)" do
      tracker.update_trailing_stop("BTCUSD", 46_000.0)
      tracker.update_trailing_stop("BTCUSD", 44_000.0)
      pos = tracker.get("BTCUSD")
      expect(pos[:peak_price]).to eq(46_000.0)
    end

    it "returns :exit when stop is hit" do
      tracker.update_trailing_stop("BTCUSD", 46_000.0)
      result = tracker.update_trailing_stop("BTCUSD", 45_000.0 * 0.984)
      expect(result).to eq(:exit)
    end

    it "returns nil when stop is not hit" do
      result = tracker.update_trailing_stop("BTCUSD", 45_500.0)
      expect(result).to be_nil
    end
  end

  describe "#close" do
    it "removes the position" do
      tracker.open(position)
      tracker.close("BTCUSD")
      expect(tracker.open?("BTCUSD")).to be(false)
    end
  end

  describe "#count" do
    it "returns number of open positions" do
      tracker.open(position)
      expect(tracker.count).to eq(1)
    end
  end

  describe "#all" do
    it "returns a snapshot of all positions" do
      tracker.open(position)
      expect(tracker.all.keys).to include("BTCUSD")
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/bot/execution/position_tracker_spec.rb
```

Expected: `LoadError`.

- [ ] **Step 3: Implement `lib/bot/execution/position_tracker.rb`**

```ruby
# frozen_string_literal: true

module Bot
  module Execution
    class PositionTracker
      def initialize
        @positions = {}
        @mutex     = Mutex.new
      end

      def open(attrs)
        symbol    = attrs[:symbol]
        trail_pct = attrs[:trail_pct] / 100.0
        entry     = attrs[:entry_price].to_f
        side      = attrs[:side]

        stop = if side == :long
                 entry * (1.0 - trail_pct)
               else
                 entry * (1.0 + trail_pct)
               end

        @mutex.synchronize do
          @positions[symbol] = attrs.merge(peak_price: entry, stop_price: stop)
        end
      end

      # Returns :exit if stop was hit, nil otherwise
      def update_trailing_stop(symbol, ltp)
        @mutex.synchronize do
          pos = @positions[symbol]
          return nil unless pos

          trail_pct = pos[:trail_pct] / 100.0

          if pos[:side] == :long
            if ltp > pos[:peak_price]
              pos[:peak_price] = ltp
              pos[:stop_price] = ltp * (1.0 - trail_pct)
            end
            return :exit if ltp <= pos[:stop_price]
          else
            if ltp < pos[:peak_price]
              pos[:peak_price] = ltp
              pos[:stop_price] = ltp * (1.0 + trail_pct)
            end
            return :exit if ltp >= pos[:stop_price]
          end

          nil
        end
      end

      def close(symbol)
        @mutex.synchronize { @positions.delete(symbol) }
      end

      def get(symbol)
        @mutex.synchronize { @positions[symbol]&.dup }
      end

      def open?(symbol)
        @mutex.synchronize { @positions.key?(symbol) }
      end

      def count
        @mutex.synchronize { @positions.size }
      end

      def all
        @mutex.synchronize { @positions.transform_values(&:dup) }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/bot/execution/position_tracker_spec.rb
```

Expected: All green.

- [ ] **Step 5: Commit**

```bash
git add lib/bot/execution/position_tracker.rb spec/bot/execution/position_tracker_spec.rb
git commit -m "feat: add PositionTracker with Mutex-protected trailing stop logic"
```

---

## Task 9: MultiTimeframe Strategy

**Files:**
- Create: `lib/bot/strategy/multi_timeframe.rb`
- Create: `spec/bot/strategy/multi_timeframe_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/bot/strategy/multi_timeframe_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/strategy/multi_timeframe"
require "bot/strategy/supertrend"
require "bot/strategy/adx"

RSpec.describe Bot::Strategy::MultiTimeframe do
  let(:config) do
    double(
      timeframe_trend: "60", timeframe_confirm: "15", timeframe_entry: "5",
      supertrend_atr_period: 3, supertrend_multiplier: 1.5,
      adx_period: 5, adx_threshold: 20,
      candles_lookback: 20, min_candles_required: 10
    )
  end

  let(:market_data) { double("MarketData") }
  let(:logger) { double("Logger", debug: nil, warn: nil, info: nil) }

  subject(:mtf) { described_class.new(config: config, market_data: market_data, logger: logger) }

  def build_candles(n, trend: :up)
    (0...n).map do |i|
      base = trend == :up ? 100.0 + i : 100.0 - i
      { open: base - 0.5, high: base + 1.5, low: base - 1.5, close: base, timestamp: Time.now.to_i + i * 300 }
    end
  end

  context "when all three timeframes are bullish and ADX is strong" do
    before do
      allow(market_data).to receive(:candles) do |params|
        build_candles(15, trend: :up).tap { |c| c.last[:timestamp] = Time.now.to_i }
      end
    end

    it "emits a LONG signal" do
      signal = mtf.evaluate("BTCUSD", current_price: 115.0)
      expect(signal&.side).to eq(:long)
      expect(signal&.symbol).to eq("BTCUSD")
    end
  end

  context "when 1H is bearish but 15M and 5M are bullish" do
    before do
      call_count = 0
      allow(market_data).to receive(:candles) do |params|
        call_count += 1
        trend = call_count == 1 ? :down : :up
        build_candles(15, trend: trend)
      end
    end

    it "returns nil (no confluent signal)" do
      expect(mtf.evaluate("BTCUSD", current_price: 85.0)).to be_nil
    end
  end

  context "when candles are insufficient" do
    before do
      allow(market_data).to receive(:candles).and_return(build_candles(5))
    end

    it "returns nil and logs a warning" do
      expect(logger).to receive(:warn).with("insufficient_candles", anything)
      expect(mtf.evaluate("BTCUSD", current_price: 100.0)).to be_nil
    end
  end

  context "stale signal prevention" do
    before do
      allow(market_data).to receive(:candles) do
        build_candles(15, trend: :up)
      end
    end

    it "does not re-emit a signal for the same candle timestamp" do
      first  = mtf.evaluate("BTCUSD", current_price: 115.0)
      second = mtf.evaluate("BTCUSD", current_price: 115.0)
      expect(first&.side).to eq(:long)
      expect(second).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/bot/strategy/multi_timeframe_spec.rb
```

Expected: `LoadError`.

- [ ] **Step 3: Implement `lib/bot/strategy/multi_timeframe.rb`**

```ruby
# frozen_string_literal: true

require "delta_exchange"
require_relative "supertrend"
require_relative "adx"
require_relative "signal"

module Bot
  module Strategy
    class MultiTimeframe
      def initialize(config:, market_data:, logger:)
        @config       = config
        @market_data  = market_data
        @logger       = logger
        @last_acted   = {}  # symbol → candle_ts of last acted-on entry candle
      end

      # Returns a Signal or nil
      def evaluate(symbol, current_price:)
        h1_candles  = fetch_candles(symbol, @config.timeframe_trend)
        m15_candles = fetch_candles(symbol, @config.timeframe_confirm)
        m5_candles  = fetch_candles(symbol, @config.timeframe_entry)

        return nil unless sufficient?(h1_candles, symbol, "1H") &&
                          sufficient?(m15_candles, symbol, "15M") &&
                          sufficient?(m5_candles, symbol, "5M")

        h1_st   = Supertrend.compute(h1_candles,  atr_period: @config.supertrend_atr_period, multiplier: @config.supertrend_multiplier)
        m15_st  = Supertrend.compute(m15_candles, atr_period: @config.supertrend_atr_period, multiplier: @config.supertrend_multiplier)
        m15_adx = ADX.compute(m15_candles, period: @config.adx_period)
        m5_st   = Supertrend.compute(m5_candles,  atr_period: @config.supertrend_atr_period, multiplier: @config.supertrend_multiplier)

        h1_dir   = h1_st.last[:direction]
        m15_dir  = m15_st.last[:direction]
        m15_adx_val = m15_adx.last[:adx]
        m5_prev_dir = m5_st[-2]&.dig(:direction)
        m5_last_dir = m5_st.last[:direction]
        m5_last_ts  = m5_candles.last[:timestamp].to_i

        return nil if h1_dir.nil? || m15_dir.nil? || m5_last_dir.nil?
        return nil if m15_adx_val.nil? || m15_adx_val < @config.adx_threshold

        # Check for fresh flip on 5M
        just_flipped = m5_prev_dir && m5_last_dir != m5_prev_dir

        return nil unless just_flipped
        return nil if @last_acted[symbol] == m5_last_ts

        side = if h1_dir == :bullish && m15_dir == :bullish && m5_last_dir == :bullish
                 :long
               elsif h1_dir == :bearish && m15_dir == :bearish && m5_last_dir == :bearish
                 :short
               end

        return nil unless side

        @last_acted[symbol] = m5_last_ts
        @logger.info("signal_generated", symbol: symbol, side: side, candle_ts: m5_last_ts)

        Signal.new(symbol: symbol, side: side, entry_price: current_price, candle_ts: m5_last_ts)
      end

      private

      def fetch_candles(symbol, resolution)
        end_ts   = Time.now.to_i
        start_ts = end_ts - (resolution.to_i * 60 * @config.candles_lookback)

        raw = @market_data.candles({
          "symbol"     => symbol,
          "resolution" => resolution,
          "start"      => start_ts,
          "end"        => end_ts
        })

        return [] unless raw.is_a?(Array)

        raw.map do |c|
          { open: c["open"].to_f, high: c["high"].to_f, low: c["low"].to_f,
            close: c["close"].to_f, timestamp: c["time"].to_i }
        end
      rescue StandardError => e
        @logger.error("candle_fetch_failed", symbol: symbol, resolution: resolution, message: e.message)
        []
      end

      def sufficient?(candles, symbol, label)
        if candles.size < @config.min_candles_required
          @logger.warn("insufficient_candles", symbol: symbol, timeframe: label, count: candles.size)
          return false
        end
        true
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/bot/strategy/multi_timeframe_spec.rb
```

Expected: All green.

- [ ] **Step 5: Commit**

```bash
git add lib/bot/strategy/multi_timeframe.rb spec/bot/strategy/multi_timeframe_spec.rb
git commit -m "feat: add MultiTimeframe strategy with MTF confluence and stale signal prevention"
```

---

## Task 10: CapitalManager and OrderManager

**Files:**
- Create: `lib/bot/account/capital_manager.rb`
- Create: `lib/bot/execution/order_manager.rb`
- Create: `spec/bot/execution/order_manager_spec.rb`

- [ ] **Step 1: Implement `lib/bot/account/capital_manager.rb`** (simple wrapper, no separate test needed)

```ruby
# frozen_string_literal: true

require "delta_exchange"

module Bot
  module Account
    class CapitalManager
      def initialize(usd_to_inr_rate:)
        @usd_to_inr_rate = usd_to_inr_rate
      end

      def available_usdt
        balance = DeltaExchange::Models::WalletBalance.find_by_asset("USDT")
        balance&.available_balance.to_f
      end

      def available_inr
        available_usdt * @usd_to_inr_rate
      end
    end
  end
end
```

- [ ] **Step 2: Write failing tests for OrderManager**

Create `spec/bot/execution/order_manager_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "bot/execution/order_manager"
require "bot/execution/position_tracker"
require "bot/strategy/signal"

RSpec.describe Bot::Execution::OrderManager do
  let(:product_cache) do
    double("ProductCache",
      product_id_for: 1,
      contract_value_for: 0.001
    )
  end

  let(:position_tracker) { Bot::Execution::PositionTracker.new }
  let(:risk_calculator)  { double("RiskCalculator", compute: 44) }
  let(:capital_manager)  { double("CapitalManager", available_usdt: 500.0) }
  let(:logger)           { double("Logger", info: nil, warn: nil, error: nil) }
  let(:notifier)         { double("TelegramNotifier", send_message: nil) }

  let(:signal) do
    Bot::Strategy::Signal.new(
      symbol: "BTCUSD", side: :long, entry_price: 45_000.0, candle_ts: 1_000_000
    )
  end

  subject(:manager) do
    described_class.new(
      config: double(
        dry_run?: true, testnet?: false, live?: false,
        risk_per_trade_pct: 1.5, trailing_stop_pct: 1.5,
        max_margin_per_position_pct: 40.0, leverage_for: 10
      ),
      product_cache: product_cache,
      position_tracker: position_tracker,
      risk_calculator: risk_calculator,
      capital_manager: capital_manager,
      logger: logger,
      notifier: notifier
    )
  end

  describe "#execute_signal" do
    it "records position in tracker on dry-run" do
      manager.execute_signal(signal)
      expect(position_tracker.open?("BTCUSD")).to be(true)
    end

    it "does not call Order.create in dry-run mode" do
      expect(DeltaExchange::Models::Order).not_to receive(:create)
      manager.execute_signal(signal)
    end

    it "logs and returns nil when lots == 0" do
      allow(risk_calculator).to receive(:compute).and_return(0)
      expect(logger).to receive(:warn).with("skip_insufficient_capital", anything)
      expect(manager.execute_signal(signal)).to be_nil
    end

    it "skips when position already open for symbol" do
      manager.execute_signal(signal)
      expect(logger).to receive(:warn).with("skip_position_exists", anything)
      manager.execute_signal(signal)
    end
  end

  describe "#close_position" do
    before { manager.execute_signal(signal) }

    it "removes position from tracker in dry-run" do
      manager.close_position("BTCUSD", exit_price: 45_500.0, reason: :trail_stop)
      expect(position_tracker.open?("BTCUSD")).to be(false)
    end

    it "sends Telegram notification on close" do
      expect(notifier).to receive(:send_message).with(a_string_including("BTCUSD"))
      manager.close_position("BTCUSD", exit_price: 45_500.0, reason: :trail_stop)
    end
  end
end
```

- [ ] **Step 3: Run to confirm failure**

```bash
bundle exec rspec spec/bot/execution/order_manager_spec.rb
```

Expected: `LoadError`.

- [ ] **Step 4: Implement `lib/bot/execution/order_manager.rb`**

```ruby
# frozen_string_literal: true

require "delta_exchange"

module Bot
  module Execution
    class OrderManager
      INR_RATE_KEY = :usd_to_inr_rate

      def initialize(config:, product_cache:, position_tracker:, risk_calculator:,
                     capital_manager:, logger:, notifier:)
        @config           = config
        @product_cache    = product_cache
        @position_tracker = position_tracker
        @risk_calculator  = risk_calculator
        @capital_manager  = capital_manager
        @logger           = logger
        @notifier         = notifier
      end

      def execute_signal(signal)
        symbol = signal.symbol

        if @position_tracker.open?(symbol)
          @logger.warn("skip_position_exists", symbol: symbol)
          return nil
        end

        leverage       = @config.leverage_for(symbol)
        available_usdt = @capital_manager.available_usdt
        contract_value = @product_cache.contract_value_for(symbol)

        lots = @risk_calculator.compute(
          available_usdt: available_usdt,
          entry_price_usd: signal.entry_price,
          leverage: leverage,
          risk_per_trade_pct: @config.risk_per_trade_pct,
          trail_pct: @config.trailing_stop_pct,
          contract_value: contract_value,
          max_margin_per_position_pct: @config.max_margin_per_position_pct
        )

        if lots.zero?
          @logger.warn("skip_insufficient_capital", symbol: symbol, available_usdt: available_usdt)
          return nil
        end

        fill_price = place_order(symbol, signal.side, lots, signal)
        return nil unless fill_price

        @position_tracker.open(
          symbol: symbol,
          side: signal.side,
          lots: lots,
          entry_price: fill_price,
          leverage: leverage,
          trail_pct: @config.trailing_stop_pct,
          entry_time: Time.now.utc
        )

        @logger.info("trade_opened", symbol: symbol, side: signal.side, entry_usd: fill_price,
                     lots: lots, leverage: leverage, mode: current_mode)
        @notifier.send_message(trade_opened_message(symbol, signal.side, fill_price, lots, leverage))
        fill_price
      rescue DeltaExchange::RateLimitError => e
        @logger.warn("rate_limited", symbol: symbol, retry_after: e.retry_after_seconds)
        sleep(e.retry_after_seconds)
        nil
      rescue DeltaExchange::ApiError => e
        @logger.error("order_failed", symbol: symbol, message: e.message)
        nil
      end

      def close_position(symbol, exit_price:, reason:)
        pos = @position_tracker.get(symbol)
        return unless pos

        place_close_order(symbol, pos[:side], pos[:lots]) unless @config.dry_run?

        @position_tracker.close(symbol)

        pnl_usd = calculate_pnl(pos, exit_price)
        duration = (Time.now.utc - pos[:entry_time]).to_i

        @logger.info("trade_closed", symbol: symbol, exit_usd: exit_price,
                     pnl_usd: pnl_usd.round(2), reason: reason, duration_seconds: duration)
        @notifier.send_message(trade_closed_message(symbol, exit_price, pnl_usd, duration, reason))
      end

      private

      def place_order(symbol, side, lots, signal)
        return fake_fill(signal) if @config.dry_run?

        product_id = @product_cache.product_id_for(symbol)
        order = DeltaExchange::Models::Order.create(
          product_id: product_id,
          size: lots,
          side: side == :long ? "buy" : "sell",
          order_type: "market_order"
        )
        order.average_fill_price.to_f
      end

      def place_close_order(symbol, side, lots)
        product_id = @product_cache.product_id_for(symbol)
        DeltaExchange::Models::Order.create(
          product_id: product_id,
          size: lots,
          side: side == :long ? "sell" : "buy",
          order_type: "market_order"
        )
      end

      def fake_fill(signal)
        # In dry-run: use the signal's entry_price (already the current LTP from PriceStore)
        signal.entry_price.to_f
      end

      def calculate_pnl(pos, exit_price)
        lots           = pos[:lots]
        contract_value = @product_cache.contract_value_for(pos[:symbol])
        entry          = pos[:entry_price]
        multiplier     = pos[:side] == :long ? 1 : -1
        multiplier * (exit_price - entry) * lots * contract_value
      end

      def current_mode
        return "dry_run"  if @config.dry_run?
        return "testnet"  if @config.testnet?
        "live"
      end

      def trade_opened_message(symbol, side, price, lots, leverage)
        emoji = side == :long ? "🟢" : "🔴"
        tag   = @config.dry_run? ? " [DRY RUN]" : ""
        stop  = side == :long ? price * (1 - @config.trailing_stop_pct / 100.0) : price * (1 + @config.trailing_stop_pct / 100.0)
        "#{emoji} #{side.to_s.upcase} #{symbol} opened#{tag}\nEntry: $#{format('%.2f', price)}\nLots: #{lots} | Leverage: #{leverage}x\nTrail Stop: $#{format('%.2f', stop)}"
      end

      def trade_closed_message(symbol, exit_price, pnl_usd, duration_secs, reason)
        hours   = duration_secs / 3600
        minutes = (duration_secs % 3600) / 60
        pnl_inr = (pnl_usd * 85).round(0)  # approximate
        sign    = pnl_usd >= 0 ? "+" : ""
        "🔴 #{symbol} closed — #{reason}\nExit: $#{format('%.2f', exit_price)}\nPnL: #{sign}$#{format('%.2f', pnl_usd)} (#{sign}₹#{pnl_inr})\nDuration: #{hours}h #{minutes}m"
      end
    end
  end
end
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/bot/execution/order_manager_spec.rb
```

Expected: All green.

- [ ] **Step 6: Commit**

```bash
git add lib/bot/account/capital_manager.rb lib/bot/execution/order_manager.rb spec/bot/execution/order_manager_spec.rb
git commit -m "feat: add CapitalManager and OrderManager with dry-run and live modes"
```

---

## Task 11: Supervisor and Runner

**Files:**
- Create: `lib/bot/supervisor.rb`
- Create: `lib/bot/runner.rb`
- Create: `bin/run`

- [ ] **Step 1: Implement `lib/bot/supervisor.rb`**

```ruby
# frozen_string_literal: true

module Bot
  class Supervisor
    MAX_CRASHES      = 5
    CRASH_WINDOW_SEC = 600  # 10 minutes
    BACKOFF_SEQUENCE = [5, 10, 30, 60].freeze

    def initialize(logger:, notifier:)
      @logger   = logger
      @notifier = notifier
      @threads  = {}
      @stop     = false
    end

    def register(name, &block)
      @threads[name] = { block: block, crashes: [], thread: nil }
    end

    def start_all
      @threads.each_key { |name| spawn_thread(name) }
    end

    def monitor
      until @stop
        @threads.each do |name, meta|
          next if meta[:thread]&.alive?

          handle_crash(name)
        end
        sleep 5
      end
    end

    def stop_all
      @stop = true
      @threads.each_value { |meta| meta[:thread]&.kill }
    end

    private

    def spawn_thread(name)
      @threads[name][:thread] = Thread.new do
        @threads[name][:block].call
      rescue StandardError => e
        @logger.error("thread_crashed", thread: name.to_s, message: e.message)
      end
    end

    def handle_crash(name)
      meta = @threads[name]
      now  = Time.now.to_i

      # Prune old crash timestamps outside window
      meta[:crashes].select! { |t| now - t < CRASH_WINDOW_SEC }
      meta[:crashes] << now

      if meta[:crashes].size >= MAX_CRASHES
        msg = "🛑 #{name} crashed #{MAX_CRASHES} times in #{CRASH_WINDOW_SEC / 60}min. Bot halted."
        @logger.error("circuit_breaker_tripped", thread: name.to_s)
        @notifier.send_message(msg)
        stop_all
        exit 1
      end

      backoff = BACKOFF_SEQUENCE[[meta[:crashes].size - 2, BACKOFF_SEQUENCE.size - 1].max]
      attempt = meta[:crashes].size

      @logger.warn("thread_restarting", thread: name.to_s, backoff: backoff, attempt: attempt)
      @notifier.send_message("⚠️ #{name} crashed. Restarting in #{backoff}s... (attempt #{attempt}/#{MAX_CRASHES})")

      sleep backoff
      spawn_thread(name)
    end
  end
end
```

- [ ] **Step 2: Implement `lib/bot/runner.rb`**

```ruby
# frozen_string_literal: true

require "delta_exchange"
require_relative "config"
require_relative "product_cache"
require_relative "supervisor"
require_relative "feed/price_store"
require_relative "feed/websocket_feed"
require_relative "strategy/multi_timeframe"
require_relative "account/capital_manager"
require_relative "execution/risk_calculator"
require_relative "execution/position_tracker"
require_relative "execution/order_manager"
require_relative "notifications/logger"
require_relative "notifications/telegram_notifier"

module Bot
  class Runner
    STRATEGY_INTERVAL_SECONDS     = 300   # 5 minutes
    TRAILING_STOP_INTERVAL_SECONDS = 15

    def initialize(config:)
      @config = config
      setup_delta_exchange
      @logger   = Notifications::Logger.new(file: config.log_file, level: config.log_level)
      @notifier = Notifications::TelegramNotifier.new(
        enabled: config.telegram_enabled?,
        token:   config.telegram_token,
        chat_id: config.telegram_chat_id
      )
    end

    def start
      @logger.info("bot_starting", mode: @config.mode, symbols: @config.symbol_names)

      products      = DeltaExchange::Models::Product.all
      @product_cache = ProductCache.new(symbols: @config.symbol_names, products: products)

      @price_store      = Feed::PriceStore.new
      @position_tracker = Execution::PositionTracker.new
      @capital_manager  = Account::CapitalManager.new(usd_to_inr_rate: @config.usd_to_inr_rate)
      @risk_calculator  = Execution::RiskCalculator.new(usd_to_inr_rate: @config.usd_to_inr_rate)

      client = DeltaExchange::Client.new
      @market_data = client.market_data

      @mtf = Strategy::MultiTimeframe.new(config: @config, market_data: @market_data, logger: @logger)

      @order_manager = Execution::OrderManager.new(
        config: @config,
        product_cache: @product_cache,
        position_tracker: @position_tracker,
        risk_calculator: @risk_calculator,
        capital_manager: @capital_manager,
        logger: @logger,
        notifier: @notifier
      )

      @ws_feed = Feed::WebsocketFeed.new(
        symbols: @config.symbol_names,
        price_store: @price_store,
        logger: @logger,
        testnet: @config.testnet?
      )

      reconcile_open_positions

      supervisor = Supervisor.new(logger: @logger, notifier: @notifier)

      supervisor.register(:websocket)      { @ws_feed.start }
      supervisor.register(:strategy)       { run_strategy_loop }
      supervisor.register(:trailing_stop)  { run_trailing_stop_loop }

      trap("INT")  { graceful_shutdown(supervisor) }
      trap("TERM") { graceful_shutdown(supervisor) }

      supervisor.start_all
      supervisor.monitor
    end

    private

    def setup_delta_exchange
      DeltaExchange.configure do |c|
        c.api_key    = ENV.fetch("DELTA_API_KEY")
        c.api_secret = ENV.fetch("DELTA_API_SECRET")
        c.testnet    = @config.testnet?
      end
    end

    def run_strategy_loop
      loop do
        @config.symbol_names.each do |symbol|
          next if @position_tracker.open?(symbol)
          next if @position_tracker.count >= @config.max_concurrent_positions

          ltp = @price_store.get(symbol)
          unless ltp
            @logger.warn("skip_no_ltp", symbol: symbol)
            next
          end

          signal = @mtf.evaluate(symbol, current_price: ltp)
          @order_manager.execute_signal(signal) if signal
        rescue DeltaExchange::RateLimitError => e
          @logger.warn("rate_limited", symbol: symbol, retry_after: e.retry_after_seconds)
          sleep(e.retry_after_seconds)
        rescue StandardError => e
          @logger.error("strategy_error", symbol: symbol, message: e.message)
        end

        sleep STRATEGY_INTERVAL_SECONDS
      end
    end

    def run_trailing_stop_loop
      loop do
        @position_tracker.all.each do |symbol, pos|
          ltp = @price_store.get(symbol)
          next unless ltp

          result = @position_tracker.update_trailing_stop(symbol, ltp)
          next unless result == :exit

          @order_manager.close_position(symbol, exit_price: ltp, reason: :trail_stop)
        end

        sleep TRAILING_STOP_INTERVAL_SECONDS
      end
    end

    def reconcile_open_positions
      api_positions = DeltaExchange::Models::Position.all
      adopted = 0

      api_positions.each do |pos|
        symbol = @product_cache.symbol_for(pos.product_id)
        next unless symbol && @config.symbol_names.include?(symbol)

        mark = pos.mark_price.to_f
        side = pos.side == "buy" ? :long : :short
        leverage = @config.leverage_for(symbol)

        @position_tracker.open(
          symbol: symbol, side: side, lots: pos.size.to_i,
          entry_price: mark, leverage: leverage,
          trail_pct: @config.trailing_stop_pct, entry_time: Time.now.utc
        )
        adopted += 1
      end

      if adopted.positive?
        @logger.info("positions_reconciled", count: adopted)
        @notifier.send_message("♻️ Bot restarted — re-adopted #{adopted} open position(s) from API")
      end
    end

    def graceful_shutdown(supervisor)
      @logger.info("bot_stopping")
      supervisor.stop_all
      @ws_feed&.stop
      exit 0
    end
  end
end
```

- [ ] **Step 3: Create `bin/run`**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv"
Dotenv.load

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "bot/runner"

config = Bot::Config.load
Bot::Runner.new(config: config).start
```

Make it executable:

```bash
chmod +x bin/run
```

- [ ] **Step 4: Create `logs/.gitignore`** (keep directory, ignore log files)

```bash
cat > logs/.gitignore << 'EOF'
*.log
!.gitkeep
EOF
```

- [ ] **Step 5: Commit**

```bash
git add lib/bot/supervisor.rb lib/bot/runner.rb bin/run logs/.gitignore
git commit -m "feat: add Supervisor with circuit breaker and Runner wiring all components"
```

---

## Task 12: Full Test Suite Run and Smoke Test

**Files:**
- No new files — validates everything works together

- [ ] **Step 1: Run the full test suite**

```bash
bundle exec rspec --format documentation
```

Expected: All tests pass. Note any failures and fix before continuing.

- [ ] **Step 2: Verify bin/run loads without error (dry-run, no API keys)**

Create a minimal `.env.test` to avoid missing key errors:

```bash
cat > .env.test << 'EOF'
DELTA_API_KEY=test
DELTA_API_SECRET=test
TZ=Asia/Kolkata
EOF
```

Then verify the file parses and config loads:

```bash
BOT_MODE=dry_run bundle exec ruby -e "
  require 'dotenv'; Dotenv.load('.env.test')
  \$LOAD_PATH.unshift('lib')
  require 'bot/config'
  c = Bot::Config.load('config/bot.yml')
  puts 'Config OK: mode=' + c.mode + ' symbols=' + c.symbol_names.join(',')
"
```

Expected: `Config OK: mode=dry_run symbols=BTCUSD,ETHUSD,SOLUSD`

- [ ] **Step 3: Commit**

```bash
git add .env.test
git commit -m "chore: add .env.test for local testing, verify full suite passes"
```

---

## Task 13: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README**

```markdown
# Delta Exchange Futures Bot

Automated multi-timeframe futures trading bot for Delta Exchange India.

## Strategy
- **1H** Supertrend → trend bias
- **15M** Supertrend + ADX → direction confirmation
- **5M** Supertrend flip → entry trigger
- **Trailing stop** (percentage-based) → exit

## Setup

```bash
cp .env.example .env
# Fill in DELTA_API_KEY, DELTA_API_SECRET, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
bundle install
```

## Configuration

Edit `config/bot.yml`:
- Set `mode: dry_run` to paper trade (no orders placed)
- Set `mode: testnet` to trade on Delta Exchange testnet
- Set `mode: live` for live trading

## Run

```bash
TZ=Asia/Kolkata bundle exec bin/run
```

## Tests

```bash
bundle exec rspec
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with setup and usage"
```

---

## Running All Tests

```bash
bundle exec rspec --format documentation
```

All tasks complete when:
- All RSpec tests pass
- `bin/run` loads without errors in dry-run mode
- Config validation rejects invalid inputs
- Supertrend and ADX produce directional output on synthetic data
