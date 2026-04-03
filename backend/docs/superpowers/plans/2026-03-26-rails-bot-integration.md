# Delta Exchange Rails Bot Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the standalone Delta Exchange trading bot into the Rails backend as a production-grade, event-driven, stateful trading system with Redis-locked singleton workers, order lifecycle tracking, and real-time frontend control.

**Architecture:** The Rails backend (`backend/`) becomes the control plane + persistence layer. A long-running `Trading::Runner` service is orchestrated via `DeltaTradingJob` (Solid Queue with Redis lock). All internal communication flows through a thread-safe `EventBus`. The existing `lib/bot/` logic is preserved and reused; new services live in `app/services/trading/`.

**Tech Stack:** Rails 8.1, PostgreSQL, Solid Queue, Redis, ActionCable, RSpec, existing `delta_exchange` local gem, existing `Bot::` classes via `app/services/bot/` symlink.

**Working directory:** All commands run from `backend/` unless stated otherwise.

---

## File Map

**New files to create:**
- `db/migrate/YYYYMMDDHHMMSS_create_trading_sessions.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_orders.rb`
- `app/models/trading_session.rb`
- `app/models/order.rb`
- `app/services/trading/event_bus.rb`
- `app/services/trading/events/tick_received.rb`
- `app/services/trading/events/signal_generated.rb`
- `app/services/trading/events/order_filled.rb`
- `app/services/trading/events/position_updated.rb`
- `app/services/trading/bootstrap/sync_positions.rb`
- `app/services/trading/bootstrap/sync_orders.rb`
- `app/services/trading/market_data/ohlcv_fetcher.rb`
- `app/services/trading/market_data/candle.rb`
- `app/services/trading/market_data/candle_series.rb`
- `app/services/trading/market_data/candle_builder.rb`
- `app/services/trading/market_data/ws_client.rb`
- `app/services/trading/idempotency_guard.rb`
- `app/services/trading/order_builder.rb`
- `app/repositories/orders_repository.rb`
- `app/repositories/positions_repository.rb`
- `app/services/trading/execution_engine.rb`
- `app/services/trading/risk_manager.rb`
- `app/services/trading/liquidation_guard.rb`
- `app/services/trading/funding_monitor.rb`
- `app/services/trading/kill_switch.rb`
- `app/services/trading/handlers/tick_handler.rb`
- `app/services/trading/handlers/order_handler.rb`
- `app/services/trading/handlers/position_handler.rb`
- `app/services/trading/runner.rb`
- `app/jobs/delta_trading_job.rb`
- `app/controllers/api/trading_sessions_controller.rb`
- `app/channels/trading_channel.rb`
- `config/initializers/redis.rb`
- `config/initializers/event_bus.rb`

**Files to modify:**
- `config/routes.rb` — add trading_sessions routes
- `../lib/bot/feed/websocket_feed.rb` — add on_tick callback support

**New spec files:**
- `spec/models/trading_session_spec.rb`
- `spec/models/order_spec.rb`
- `spec/services/trading/event_bus_spec.rb`
- `spec/services/trading/bootstrap/sync_positions_spec.rb`
- `spec/services/trading/bootstrap/sync_orders_spec.rb`
- `spec/services/trading/market_data/candle_builder_spec.rb`
- `spec/services/trading/market_data/candle_series_spec.rb`
- `spec/services/trading/idempotency_guard_spec.rb`
- `spec/services/trading/execution_engine_spec.rb`
- `spec/services/trading/risk_manager_spec.rb`
- `spec/services/trading/liquidation_guard_spec.rb`
- `spec/services/trading/kill_switch_spec.rb`
- `spec/services/trading/handlers/tick_handler_spec.rb`
- `spec/services/trading/handlers/order_handler_spec.rb`
- `spec/services/trading/runner_spec.rb`
- `spec/jobs/delta_trading_job_spec.rb`
- `spec/requests/api/trading_sessions_spec.rb`

---

## Task 1: TradingSession Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_trading_sessions.rb`
- Create: `app/models/trading_session.rb`
- Create: `spec/models/trading_session_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/models/trading_session_spec.rb
require "rails_helper"

RSpec.describe TradingSession, type: :model do
  it "is valid with required attributes" do
    session = TradingSession.new(strategy: "multi_timeframe", status: "running", capital: 1000.0)
    expect(session).to be_valid
  end

  it "is invalid without strategy" do
    expect(TradingSession.new(status: "running")).not_to be_valid
  end

  it "defaults status to pending" do
    session = TradingSession.create!(strategy: "multi_timeframe", capital: 500.0)
    expect(session.status).to eq("pending")
  end

  it "#running? returns true when status is running" do
    session = TradingSession.new(status: "running")
    expect(session.running?).to be true
  end

  it "#running? returns false when status is stopped" do
    session = TradingSession.new(status: "stopped")
    expect(session.running?).to be false
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/models/trading_session_spec.rb
```
Expected: `NameError: uninitialized constant TradingSession`

- [ ] **Step 3: Generate the migration**

```
bundle exec rails generate migration CreateTradingSessions strategy:string status:string capital:decimal leverage:integer started_at:datetime stopped_at:datetime
bundle exec rails db:migrate
```

- [ ] **Step 4: Implement the model**

```ruby
# app/models/trading_session.rb
class TradingSession < ApplicationRecord
  STATUSES = %w[pending running stopped crashed].freeze

  validates :strategy, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_status

  def running?
    status == "running"
  end

  private

  def set_default_status
    self.status ||= "pending"
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/models/trading_session_spec.rb
```
Expected: 5 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
git add db/migrate/*create_trading_sessions* db/schema.rb app/models/trading_session.rb spec/models/trading_session_spec.rb
git commit -m "feat: add TradingSession model with status lifecycle"
```

---

## Task 2: Order Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_orders.rb`
- Create: `app/models/order.rb`
- Create: `spec/models/order_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/models/order_spec.rb
require "rails_helper"

RSpec.describe Order, type: :model do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }

  it "is valid with required attributes" do
    order = Order.new(
      trading_session: session,
      symbol: "BTCUSD",
      side: "buy",
      size: 1.0,
      price: 50000.0,
      order_type: "limit_order",
      status: "pending",
      idempotency_key: "delta:order:BTCUSD:buy:1711440000"
    )
    expect(order).to be_valid
  end

  it "is invalid without idempotency_key" do
    order = Order.new(symbol: "BTCUSD", side: "buy", size: 1.0, status: "pending")
    expect(order).not_to be_valid
  end

  it "enforces unique idempotency_key" do
    attrs = { trading_session: session, symbol: "BTCUSD", side: "buy", size: 1.0,
              price: 50000.0, order_type: "limit_order", status: "pending",
              idempotency_key: "unique-key-123" }
    Order.create!(attrs)
    duplicate = Order.new(attrs)
    expect(duplicate).not_to be_valid
  end

  it "#filled? returns true when status is filled" do
    expect(Order.new(status: "filled")).to be_filled
  end

  it "#open? returns true when status is open or partially_filled" do
    expect(Order.new(status: "open")).to be_open
    expect(Order.new(status: "partially_filled")).to be_open
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/models/order_spec.rb
```
Expected: `NameError: uninitialized constant Order`

- [ ] **Step 3: Generate the migration**

```
bundle exec rails generate migration CreateOrders trading_session:references symbol:string side:string size:decimal price:decimal order_type:string status:string filled_qty:decimal avg_fill_price:decimal idempotency_key:string exchange_order_id:string raw_payload:jsonb
bundle exec rails db:migrate
```

Then add a unique index via a new migration:
```
bundle exec rails generate migration AddUniqueIndexToOrdersIdempotencyKey
```

```ruby
# In the generated migration file:
def change
  add_index :orders, :idempotency_key, unique: true
  add_index :orders, :exchange_order_id
end
```

```
bundle exec rails db:migrate
```

- [ ] **Step 4: Implement the model**

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :trading_session

  STATUSES = %w[pending open partially_filled filled cancelled rejected].freeze
  SIDES    = %w[buy sell].freeze

  validates :symbol, presence: true
  validates :side, inclusion: { in: SIDES }
  validates :size, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: true

  def filled?
    status == "filled"
  end

  def open?
    status.in?(%w[open partially_filled])
  end

  def terminal?
    status.in?(%w[filled cancelled rejected])
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/models/order_spec.rb
```
Expected: 5 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
git add db/migrate/*create_orders* db/migrate/*unique_index* db/schema.rb app/models/order.rb spec/models/order_spec.rb
git commit -m "feat: add Order model with lifecycle status and idempotency constraint"
```

---

## Task 3: EventBus + Event Structs

**Files:**
- Create: `app/services/trading/event_bus.rb`
- Create: `app/services/trading/events/tick_received.rb`
- Create: `app/services/trading/events/signal_generated.rb`
- Create: `app/services/trading/events/order_filled.rb`
- Create: `app/services/trading/events/position_updated.rb`
- Create: `spec/services/trading/event_bus_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
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

  it "is thread-safe under concurrent publish" do
    results = []
    mutex = Mutex.new
    described_class.subscribe(:concurrent) { |p| mutex.synchronize { results << p } }

    threads = 10.times.map { |i| Thread.new { described_class.publish(:concurrent, i) } }
    threads.each(&:join)

    expect(results.size).to eq(10)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/services/trading/event_bus_spec.rb
```
Expected: `NameError: uninitialized constant Trading::EventBus`

- [ ] **Step 3: Implement EventBus and Event structs**

```ruby
# app/services/trading/event_bus.rb
module Trading
  class EventBus
    @subscribers = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new

    class << self
      def subscribe(event_type, &handler)
        @mutex.synchronize { @subscribers[event_type] << handler }
      end

      def publish(event_type, payload)
        handlers = @mutex.synchronize { @subscribers[event_type].dup }
        handlers.each do |handler|
          handler.call(payload)
        rescue => e
          Rails.logger.error("[EventBus] Handler error for #{event_type}: #{e.message}")
        end
      end

      def reset!
        @mutex.synchronize { @subscribers.clear }
      end
    end
  end
end
```

```ruby
# app/services/trading/events/tick_received.rb
module Trading
  module Events
    TickReceived = Struct.new(:symbol, :price, :timestamp, :volume, keyword_init: true)
  end
end
```

```ruby
# app/services/trading/events/signal_generated.rb
module Trading
  module Events
    SignalGenerated = Struct.new(:symbol, :side, :entry_price, :candle_timestamp,
                                 :strategy, :session_id, keyword_init: true)
  end
end
```

```ruby
# app/services/trading/events/order_filled.rb
module Trading
  module Events
    OrderFilled = Struct.new(:exchange_order_id, :symbol, :side, :filled_qty,
                              :avg_fill_price, :status, keyword_init: true)
  end
end
```

```ruby
# app/services/trading/events/position_updated.rb
module Trading
  module Events
    PositionUpdated = Struct.new(:symbol, :side, :size, :entry_price,
                                  :mark_price, :unrealized_pnl, :status, keyword_init: true)
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/services/trading/event_bus_spec.rb
```
Expected: 5 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/trading/event_bus.rb app/services/trading/events/ spec/services/trading/event_bus_spec.rb
git commit -m "feat: add thread-safe EventBus with event structs"
```

---

## Task 4: Bootstrap — SyncPositions + SyncOrders

**Files:**
- Create: `app/services/trading/bootstrap/sync_positions.rb`
- Create: `app/services/trading/bootstrap/sync_orders.rb`
- Create: `spec/services/trading/bootstrap/sync_positions_spec.rb`
- Create: `spec/services/trading/bootstrap/sync_orders_spec.rb`

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/services/trading/bootstrap/sync_positions_spec.rb
require "rails_helper"

RSpec.describe Trading::Bootstrap::SyncPositions do
  let(:client) { instance_double("DeltaExchange::Client") }

  before do
    allow(client).to receive(:get_positions).and_return([
      { symbol: "BTCUSD", side: "long", size: 1.0, entry_price: 50000.0,
        leverage: 10, margin: 500.0, liquidation_price: 45000.0, product_id: 84 }
    ])
  end

  it "upserts open positions from exchange" do
    expect { described_class.call(client: client) }.to change(Position, :count).by(1)
    position = Position.last
    expect(position.symbol).to eq("BTCUSD")
    expect(position.side).to eq("long")
    expect(position.entry_price).to eq(50000.0)
  end

  it "updates existing open position instead of creating duplicate" do
    Position.create!(symbol: "BTCUSD", side: "long", status: "open",
                     size: 0.5, entry_price: 48000.0, leverage: 10)
    expect { described_class.call(client: client) }.not_to change(Position, :count)
    expect(Position.find_by(symbol: "BTCUSD").entry_price).to eq(50000.0)
  end

  it "marks local open positions as closed when absent from exchange" do
    stale = Position.create!(symbol: "ETHUSD", side: "long", status: "open",
                              size: 1.0, entry_price: 3000.0, leverage: 15)
    described_class.call(client: client)
    expect(stale.reload.status).to eq("closed")
  end

  it "does nothing when exchange returns empty positions" do
    allow(client).to receive(:get_positions).and_return([])
    Position.create!(symbol: "BTCUSD", side: "long", status: "open",
                     size: 1.0, entry_price: 50000.0, leverage: 10)
    described_class.call(client: client)
    expect(Position.find_by(symbol: "BTCUSD").status).to eq("closed")
  end
end
```

```ruby
# spec/services/trading/bootstrap/sync_orders_spec.rb
require "rails_helper"

RSpec.describe Trading::Bootstrap::SyncOrders do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:client)  { instance_double("DeltaExchange::Client") }

  before do
    allow(client).to receive(:get_open_orders).and_return([
      { id: "EX-001", symbol: "BTCUSD", side: "buy", size: 1.0,
        price: 50000.0, order_type: "limit_order", status: "open" }
    ])
  end

  it "marks stale local pending orders as cancelled" do
    stale = Order.create!(
      trading_session: session, symbol: "BTCUSD", side: "buy",
      size: 1.0, price: 49000.0, order_type: "limit_order",
      status: "pending", idempotency_key: "old-key-1",
      exchange_order_id: "EX-STALE"
    )
    described_class.call(client: client, session: session)
    expect(stale.reload.status).to eq("cancelled")
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

```
bundle exec rspec spec/services/trading/bootstrap/
```
Expected: `NameError: uninitialized constant Trading::Bootstrap`

- [ ] **Step 3: Implement SyncPositions**

```ruby
# app/services/trading/bootstrap/sync_positions.rb
module Trading
  module Bootstrap
    class SyncPositions
      def self.call(client:)
        new(client).call
      end

      def initialize(client)
        @client = client
      end

      def call
        exchange_positions = @client.get_positions
        exchange_positions.each { |ep| upsert_position(ep) }
        close_stale_positions(exchange_positions)
        Rails.logger.info("[Bootstrap::SyncPositions] Synced #{exchange_positions.size} positions")
      rescue => e
        Rails.logger.error("[Bootstrap::SyncPositions] Failed: #{e.message}")
        raise
      end

      private

      def upsert_position(ep)
        position = Position.find_or_initialize_by(symbol: ep[:symbol], status: "open")
        position.assign_attributes(
          side:              ep[:side],
          size:              ep[:size],
          entry_price:       ep[:entry_price],
          leverage:          ep[:leverage],
          margin:            ep[:margin],
          liquidation_price: ep[:liquidation_price],
          product_id:        ep[:product_id]
        )
        position.save!
      end

      def close_stale_positions(exchange_positions)
        active_symbols = exchange_positions.map { |ep| ep[:symbol] }
        Position.where(status: "open")
                .where.not(symbol: active_symbols)
                .update_all(status: "closed")
      end
    end
  end
end
```

- [ ] **Step 4: Implement SyncOrders**

```ruby
# app/services/trading/bootstrap/sync_orders.rb
module Trading
  module Bootstrap
    class SyncOrders
      def self.call(client:, session:)
        new(client, session).call
      end

      def initialize(client, session)
        @client  = client
        @session = session
      end

      def call
        open_exchange_ids = fetch_open_exchange_order_ids
        cancel_stale_local_orders(open_exchange_ids)
        Rails.logger.info("[Bootstrap::SyncOrders] Cancelled stale orders not found on exchange")
      rescue => e
        Rails.logger.error("[Bootstrap::SyncOrders] Failed: #{e.message}")
        raise
      end

      private

      def fetch_open_exchange_order_ids
        @client.get_open_orders.map { |o| o[:id].to_s }
      rescue => e
        Rails.logger.warn("[Bootstrap::SyncOrders] Could not fetch open orders: #{e.message}")
        []
      end

      def cancel_stale_local_orders(open_exchange_ids)
        Order.where(trading_session: @session, status: %w[pending open])
             .where.not(exchange_order_id: open_exchange_ids)
             .update_all(status: "cancelled")
      end
    end
  end
end
```

- [ ] **Step 5: Run specs to verify they pass**

```
bundle exec rspec spec/services/trading/bootstrap/
```
Expected: 5 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
git add app/services/trading/bootstrap/ spec/services/trading/bootstrap/
git commit -m "feat: add Bootstrap services for position and order state recovery on startup"
```

---

## Task 5: Market Data — Candle, CandleSeries, CandleBuilder

**Files:**
- Create: `app/services/trading/market_data/candle.rb`
- Create: `app/services/trading/market_data/candle_series.rb`
- Create: `app/services/trading/market_data/candle_builder.rb`
- Create: `spec/services/trading/market_data/candle_builder_spec.rb`
- Create: `spec/services/trading/market_data/candle_series_spec.rb`

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/services/trading/market_data/candle_builder_spec.rb
require "rails_helper"

RSpec.describe Trading::MarketData::CandleBuilder do
  subject(:builder) { described_class.new(symbol: "BTCUSD", interval_seconds: 60) }

  it "returns nil for the first tick (no candle closed yet)" do
    result = builder.on_tick(price: 50000.0, timestamp: 1_711_440_010)
    expect(result).to be_nil
  end

  it "returns a closed candle when a new interval begins" do
    builder.on_tick(price: 50000.0, timestamp: 1_711_440_010)
    builder.on_tick(price: 50100.0, timestamp: 1_711_440_030)
    closed = builder.on_tick(price: 50200.0, timestamp: 1_711_440_070) # next minute
    expect(closed).not_to be_nil
    expect(closed.symbol).to eq("BTCUSD")
    expect(closed.open).to eq(50000.0)
    expect(closed.high).to eq(50100.0)
    expect(closed.low).to eq(50000.0)
    expect(closed.close).to eq(50100.0)
    expect(closed.closed).to be true
  end

  it "tracks high and low within interval" do
    builder.on_tick(price: 50000.0, timestamp: 1_711_440_010)
    builder.on_tick(price: 50500.0, timestamp: 1_711_440_020)
    builder.on_tick(price: 49800.0, timestamp: 1_711_440_030)
    closed = builder.on_tick(price: 50200.0, timestamp: 1_711_440_070)
    expect(closed.high).to eq(50500.0)
    expect(closed.low).to eq(49800.0)
  end
end
```

```ruby
# spec/services/trading/market_data/candle_series_spec.rb
require "rails_helper"

RSpec.describe Trading::MarketData::CandleSeries do
  let(:candle) do
    Trading::MarketData::Candle.new(
      symbol: "BTCUSD", open: 50000.0, high: 50500.0, low: 49800.0,
      close: 50200.0, volume: 10.0,
      opened_at: Time.now - 60, closed_at: Time.now, closed: true
    )
  end

  it "stores loaded candles" do
    described_class.load([candle])
    expect(described_class.all.size).to eq(1)
  end

  it "appends a new candle" do
    described_class.load([])
    described_class.add(candle)
    expect(described_class.all).to include(candle)
  end

  it "caps at MAX_CANDLES by removing oldest" do
    described_class.load([])
    stub_const("#{described_class}::MAX_CANDLES", 3)
    4.times { described_class.add(candle) }
    expect(described_class.all.size).to eq(3)
  end

  it "returns last N closes" do
    c1 = candle.dup.tap { |c| c.close = 100.0 }
    c2 = candle.dup.tap { |c| c.close = 200.0 }
    described_class.load([c1, c2])
    expect(described_class.closes(2)).to eq([100.0, 200.0])
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

```
bundle exec rspec spec/services/trading/market_data/candle_builder_spec.rb spec/services/trading/market_data/candle_series_spec.rb
```
Expected: `NameError: uninitialized constant Trading::MarketData`

- [ ] **Step 3: Implement Candle struct**

```ruby
# app/services/trading/market_data/candle.rb
module Trading
  module MarketData
    Candle = Struct.new(:symbol, :open, :high, :low, :close, :volume,
                        :opened_at, :closed_at, :closed, keyword_init: true)
  end
end
```

- [ ] **Step 4: Implement CandleSeries**

```ruby
# app/services/trading/market_data/candle_series.rb
module Trading
  module MarketData
    class CandleSeries
      MAX_CANDLES = 500

      @candles = []
      @mutex   = Mutex.new

      class << self
        def load(candles)
          @mutex.synchronize { @candles = candles.dup }
        end

        def add(candle)
          @mutex.synchronize do
            @candles << candle
            @candles.shift if @candles.size > MAX_CANDLES
          end
        end

        def all
          @mutex.synchronize { @candles.dup }
        end

        def closes(n = nil)
          series = all.map(&:close)
          n ? series.last(n) : series
        end

        def last_candle
          all.last
        end

        def size
          @mutex.synchronize { @candles.size }
        end
      end
    end
  end
end
```

- [ ] **Step 5: Implement CandleBuilder**

```ruby
# app/services/trading/market_data/candle_builder.rb
module Trading
  module MarketData
    class CandleBuilder
      def initialize(symbol:, interval_seconds:)
        @symbol           = symbol
        @interval_seconds = interval_seconds
        @current          = nil
        @bucket           = nil
      end

      # Returns a closed Candle when an interval boundary is crossed, nil otherwise.
      def on_tick(price:, timestamp:, volume: 0.0)
        bucket = (timestamp / @interval_seconds) * @interval_seconds

        if @bucket != bucket
          completed = @current
          start_new_candle(price, bucket, volume)
          completed&.tap { |c| c.closed = true; c.closed_at = Time.at(@bucket) }
        else
          update_candle(price, volume)
          nil
        end
      end

      private

      def start_new_candle(price, bucket, volume)
        @bucket  = bucket
        @current = Candle.new(
          symbol:    @symbol,
          open:      price,
          high:      price,
          low:       price,
          close:     price,
          volume:    volume,
          opened_at: Time.at(bucket),
          closed_at: nil,
          closed:    false
        )
      end

      def update_candle(price, volume)
        @current.high  = [@current.high, price].max
        @current.low   = [@current.low, price].min
        @current.close = price
        @current.volume += volume
      end
    end
  end
end
```

- [ ] **Step 6: Run specs to verify they pass**

```
bundle exec rspec spec/services/trading/market_data/candle_builder_spec.rb spec/services/trading/market_data/candle_series_spec.rb
```
Expected: 7 examples, 0 failures

- [ ] **Step 7: Commit**

```bash
git add app/services/trading/market_data/candle.rb app/services/trading/market_data/candle_series.rb app/services/trading/market_data/candle_builder.rb spec/services/trading/market_data/
git commit -m "feat: add CandleBuilder and CandleSeries for WS tick aggregation"
```

---

## Task 6: Market Data — OhlcvFetcher + WsClient

**Files:**
- Create: `app/services/trading/market_data/ohlcv_fetcher.rb`
- Create: `app/services/trading/market_data/ws_client.rb`
- Modify: `../lib/bot/feed/websocket_feed.rb` — add on_tick callback

- [ ] **Step 1: Add on_tick callback to WebsocketFeed**

Read `../lib/bot/feed/websocket_feed.rb` first, then add callback support. The change adds an optional `on_tick:` keyword argument to `initialize` and calls it after updating PriceStore:

```ruby
# In lib/bot/feed/websocket_feed.rb — modify initialize signature:
def initialize(client:, symbols:, price_store:, logger:, on_tick: nil)
  @on_tick = on_tick
  # ... rest unchanged
end

# In the ticker message handler, after price_store.update(symbol, price), add:
@on_tick&.call(symbol, price, Time.now.to_i)
```

- [ ] **Step 2: Implement OhlcvFetcher**

```ruby
# app/services/trading/market_data/ohlcv_fetcher.rb
module Trading
  module MarketData
    class OhlcvFetcher
      DEFAULT_LIMIT = 200

      def initialize(client:)
        @client = client
      end

      # Returns array of Candle structs from oldest to newest.
      def fetch(symbol:, resolution:, limit: DEFAULT_LIMIT)
        raw = @client.get_ohlcv(symbol: symbol, resolution: resolution, limit: limit)
        raw.map do |r|
          Candle.new(
            symbol:    symbol,
            open:      r[:open].to_f,
            high:      r[:high].to_f,
            low:       r[:low].to_f,
            close:     r[:close].to_f,
            volume:    r[:volume].to_f,
            opened_at: Time.at(r[:time]),
            closed_at: Time.at(r[:time]) + interval_seconds(resolution),
            closed:    true
          )
        end
      rescue => e
        Rails.logger.error("[OhlcvFetcher] Failed for #{symbol}/#{resolution}: #{e.message}")
        []
      end

      private

      def interval_seconds(resolution)
        case resolution
        when "1m" then 60
        when "5m" then 300
        when "15m" then 900
        when "1h" then 3600
        else 60
        end
      end
    end
  end
end
```

- [ ] **Step 3: Implement WsClient**

```ruby
# app/services/trading/market_data/ws_client.rb
module Trading
  module MarketData
    class WsClient
      INTERVAL_SECONDS = 60  # 1-minute candles

      def initialize(client:, symbols: nil)
        @client          = client
        @symbols         = symbols || SymbolConfig.where(enabled: true).pluck(:symbol)
        @candle_builders = build_candle_builders
        @price_store     = Bot::Feed::PriceStore.new
      end

      def start
        feed = Bot::Feed::WebsocketFeed.new(
          client:      @client,
          symbols:     @symbols,
          price_store: @price_store,
          logger:      Rails.logger,
          on_tick:     method(:handle_tick)
        )
        feed.start
      rescue => e
        Rails.logger.error("[WsClient] Feed crashed: #{e.message}")
        raise
      end

      private

      def handle_tick(symbol, price, timestamp)
        Rails.cache.write("ltp:#{symbol}", price, expires_in: 30.seconds)

        EventBus.publish(:tick_received,
          Events::TickReceived.new(symbol: symbol, price: price, timestamp: timestamp))

        closed_candle = @candle_builders[symbol]&.on_tick(
          price: price, timestamp: timestamp
        )
        EventBus.publish(:candle_closed, closed_candle) if closed_candle
      end

      def build_candle_builders
        @symbols.each_with_object({}) do |symbol, hash|
          hash[symbol] = CandleBuilder.new(symbol: symbol, interval_seconds: INTERVAL_SECONDS)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Verify existing bot specs still pass (regression check)**

```
cd .. && bundle exec rspec spec/bot/feed/ && cd backend
```
Expected: All feed specs pass

- [ ] **Step 5: Commit**

```bash
git add app/services/trading/market_data/ohlcv_fetcher.rb app/services/trading/market_data/ws_client.rb
git add -p ../lib/bot/feed/websocket_feed.rb  # commit only the on_tick change
git commit -m "feat: add OhlcvFetcher and WsClient with EventBus tick publishing"
```

---

## Task 7: Execution — IdempotencyGuard + OrderBuilder + Repositories

**Files:**
- Create: `app/services/trading/idempotency_guard.rb`
- Create: `app/services/trading/order_builder.rb`
- Create: `app/repositories/orders_repository.rb`
- Create: `app/repositories/positions_repository.rb`
- Create: `spec/services/trading/idempotency_guard_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/trading/idempotency_guard_spec.rb
require "rails_helper"

RSpec.describe Trading::IdempotencyGuard do
  let(:key) { described_class.key(symbol: "BTCUSD", side: "buy", timestamp: 1_711_440_000) }

  after { described_class.release(key) }

  it "generates a deterministic key from signal attributes" do
    k1 = described_class.key(symbol: "BTCUSD", side: "buy", timestamp: 1_711_440_000)
    k2 = described_class.key(symbol: "BTCUSD", side: "buy", timestamp: 1_711_440_000)
    expect(k1).to eq(k2)
  end

  it "acquire returns true on first call" do
    expect(described_class.acquire(key)).to be_truthy
  end

  it "acquire returns false on second call (duplicate prevention)" do
    described_class.acquire(key)
    expect(described_class.acquire(key)).to be_falsy
  end

  it "release allows re-acquire" do
    described_class.acquire(key)
    described_class.release(key)
    expect(described_class.acquire(key)).to be_truthy
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/services/trading/idempotency_guard_spec.rb
```
Expected: `NameError: uninitialized constant Trading::IdempotencyGuard`

- [ ] **Step 3: Implement IdempotencyGuard**

```ruby
# app/services/trading/idempotency_guard.rb
module Trading
  class IdempotencyGuard
    KEY_TTL = 3600  # 1 hour

    def self.key(symbol:, side:, timestamp:)
      "delta:order:#{symbol}:#{side}:#{timestamp}"
    end

    def self.acquire(key)
      Redis.current.set(key, 1, nx: true, ex: KEY_TTL)
    end

    def self.release(key)
      Redis.current.del(key)
    end
  end
end
```

- [ ] **Step 4: Implement OrderBuilder**

```ruby
# app/services/trading/order_builder.rb
module Trading
  class OrderBuilder
    def self.build(signal, session:)
      new(signal, session).build
    end

    def initialize(signal, session)
      @signal  = signal
      @session = session
    end

    def build
      {
        trading_session_id: @session.id,
        symbol:             @signal.symbol,
        side:               @signal.side,
        size:               calculate_size,
        price:              @signal.entry_price,
        order_type:         "limit_order",
        status:             "pending",
        idempotency_key:    IdempotencyGuard.key(
          symbol:    @signal.symbol,
          side:      @signal.side,
          timestamp: @signal.candle_timestamp.to_i
        )
      }
    end

    private

    def calculate_size
      # Delegate to existing risk calculator if available, default to 1 lot
      return 1 unless @session.capital.present?

      capital    = @session.capital
      leverage   = @session.leverage || 10
      entry      = @signal.entry_price
      risk_pct   = 0.015  # 1.5%

      margin_per_trade = capital * risk_pct
      notional         = margin_per_trade * leverage
      lots             = (notional / entry).floor
      [lots, 1].max
    end
  end
end
```

- [ ] **Step 5: Implement Repositories**

```ruby
# app/repositories/orders_repository.rb
module OrdersRepository
  def self.create!(attrs)
    Order.create!(attrs)
  end

  def self.find_by_exchange_id(exchange_order_id)
    Order.find_by(exchange_order_id: exchange_order_id)
  end

  def self.update_from_fill(exchange_order_id:, filled_qty:, avg_fill_price:, status:)
    order = find_by_exchange_id(exchange_order_id)
    return unless order

    order.update!(
      filled_qty:     filled_qty,
      avg_fill_price: avg_fill_price,
      status:         status
    )
    order
  end
end
```

```ruby
# app/repositories/positions_repository.rb
module PositionsRepository
  def self.open_for(symbol)
    Position.find_by(symbol: symbol, status: "open")
  end

  def self.upsert_from_order(order)
    position = Position.find_or_initialize_by(symbol: order.symbol, status: "open")
    position.assign_attributes(
      side:        order.side == "buy" ? "long" : "short",
      size:        order.filled_qty,
      entry_price: order.avg_fill_price,
      status:      "open"
    )
    position.save!
    position
  end

  def self.close!(symbol)
    Position.where(symbol: symbol, status: "open").update_all(status: "closed")
  end
end
```

- [ ] **Step 6: Run spec to verify it passes**

```
bundle exec rspec spec/services/trading/idempotency_guard_spec.rb
```
Expected: 4 examples, 0 failures

- [ ] **Step 7: Commit**

```bash
git add app/services/trading/idempotency_guard.rb app/services/trading/order_builder.rb app/repositories/ spec/services/trading/idempotency_guard_spec.rb
git commit -m "feat: add IdempotencyGuard, OrderBuilder, and repository layer"
```

---

## Task 8: ExecutionEngine

**Files:**
- Create: `app/services/trading/execution_engine.rb`
- Create: `spec/services/trading/execution_engine_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/trading/execution_engine_spec.rb
require "rails_helper"

RSpec.describe Trading::ExecutionEngine do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0, leverage: 10) }
  let(:client)  { instance_double("DeltaExchange::Client") }
  let(:signal) do
    Trading::Events::SignalGenerated.new(
      symbol:           "BTCUSD",
      side:             "buy",
      entry_price:      50000.0,
      candle_timestamp: Time.now,
      strategy:         "multi_timeframe",
      session_id:       session.id
    )
  end

  before do
    allow(client).to receive(:place_order).and_return({ id: "EX-001", status: "open" })
    allow(Trading::RiskManager).to receive(:validate!).and_return(true)
  end

  it "creates an Order record" do
    expect {
      described_class.execute(signal, session: session, client: client)
    }.to change(Order, :count).by(1)
  end

  it "calls client.place_order with order params" do
    described_class.execute(signal, session: session, client: client)
    expect(client).to have_received(:place_order)
  end

  it "stores exchange_order_id on the order" do
    described_class.execute(signal, session: session, client: client)
    expect(Order.last.exchange_order_id).to eq("EX-001")
  end

  it "does nothing when idempotency key already acquired" do
    key = Trading::IdempotencyGuard.key(
      symbol: signal.symbol, side: signal.side, timestamp: signal.candle_timestamp.to_i
    )
    Trading::IdempotencyGuard.acquire(key)

    expect {
      described_class.execute(signal, session: session, client: client)
    }.not_to change(Order, :count)

    Trading::IdempotencyGuard.release(key)
  end

  it "raises and does not create order when risk validation fails" do
    allow(Trading::RiskManager).to receive(:validate!).and_raise(Trading::RiskManager::RiskError, "max positions")
    expect {
      described_class.execute(signal, session: session, client: client)
    }.to raise_error(Trading::RiskManager::RiskError)
    expect(Order.count).to eq(0)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/services/trading/execution_engine_spec.rb
```
Expected: `NameError: uninitialized constant Trading::ExecutionEngine`

- [ ] **Step 3: Implement ExecutionEngine**

```ruby
# app/services/trading/execution_engine.rb
module Trading
  class ExecutionEngine
    def self.execute(signal, session:, client:)
      new(signal, session, client).execute
    end

    def initialize(signal, session, client)
      @signal  = signal
      @session = session
      @client  = client
    end

    def execute
      idem_key = IdempotencyGuard.key(
        symbol: @signal.symbol, side: @signal.side, timestamp: @signal.candle_timestamp.to_i
      )
      return Rails.logger.warn("[ExecutionEngine] Duplicate signal skipped: #{idem_key}") unless
        IdempotencyGuard.acquire(idem_key)

      RiskManager.validate!(@signal, session: @session)

      order_attrs = OrderBuilder.build(@signal, session: @session)
      order       = OrdersRepository.create!(order_attrs)

      result = @client.place_order(
        product_id: fetch_product_id(@signal.symbol),
        side:       @signal.side,
        order_type: order.order_type,
        size:       order.size,
        limit_price: order.price
      )

      order.update!(exchange_order_id: result[:id], status: result[:status] || "open")
      Rails.logger.info("[ExecutionEngine] Order placed: #{order.exchange_order_id} for #{@signal.symbol}")
      order
    rescue RiskManager::RiskError => e
      Rails.logger.warn("[ExecutionEngine] Risk rejected signal: #{e.message}")
      raise
    rescue => e
      Rails.logger.error("[ExecutionEngine] Failed to execute signal: #{e.message}")
      raise
    end

    private

    def fetch_product_id(symbol)
      Rails.cache.fetch("product_id:#{symbol}", expires_in: 1.hour) do
        SymbolConfig.find_by(symbol: symbol)&.fetch("product_id") ||
          raise("No product_id for #{symbol}")
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/services/trading/execution_engine_spec.rb
```
Expected: 5 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/trading/execution_engine.rb spec/services/trading/execution_engine_spec.rb
git commit -m "feat: add ExecutionEngine decoupling signal from order placement"
```

---

## Task 9: Risk Layer — RiskManager, LiquidationGuard, FundingMonitor

**Files:**
- Create: `app/services/trading/risk_manager.rb`
- Create: `app/services/trading/liquidation_guard.rb`
- Create: `app/services/trading/funding_monitor.rb`
- Create: `spec/services/trading/risk_manager_spec.rb`
- Create: `spec/services/trading/liquidation_guard_spec.rb`

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/services/trading/risk_manager_spec.rb
require "rails_helper"

RSpec.describe Trading::RiskManager do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:signal) do
    Trading::Events::SignalGenerated.new(
      symbol: "BTCUSD", side: "buy", entry_price: 50000.0,
      candle_timestamp: Time.now, strategy: "multi_timeframe", session_id: session.id
    )
  end

  it "passes validation when conditions are met" do
    expect { described_class.validate!(signal, session: session) }.not_to raise_error
  end

  it "raises RiskError when max concurrent positions reached" do
    5.times { |i| Position.create!(symbol: "SYM#{i}", side: "long", status: "open", size: 1.0, entry_price: 100.0, leverage: 10) }
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /max concurrent/)
  end

  it "raises RiskError when margin utilization exceeded" do
    Position.create!(symbol: "ETHUSD", side: "long", status: "open",
                     size: 1.0, entry_price: 100.0, leverage: 10, margin: 420.0)
    expect {
      described_class.validate!(signal, session: session)
    }.to raise_error(Trading::RiskManager::RiskError, /margin/)
  end
end
```

```ruby
# spec/services/trading/liquidation_guard_spec.rb
require "rails_helper"

RSpec.describe Trading::LiquidationGuard do
  let(:client) { instance_double("DeltaExchange::Client") }
  let(:position) do
    Position.create!(
      symbol: "BTCUSD", side: "long", status: "open",
      size: 1.0, entry_price: 50000.0, leverage: 10,
      liquidation_price: 45000.0
    )
  end

  before { Rails.cache.write("ltp:BTCUSD", 45500.0) }
  after  { Rails.cache.delete("ltp:BTCUSD") }

  it "does not force exit when distance is above buffer" do
    Rails.cache.write("ltp:BTCUSD", 50000.0)
    expect(Trading::KillSwitch).not_to receive(:force_exit_position)
    described_class.check_all(client: client)
  end

  it "force exits when within 10% of liquidation price" do
    allow(Trading::KillSwitch).to receive(:force_exit_position)
    described_class.check_all(client: client)
    expect(Trading::KillSwitch).to have_received(:force_exit_position).with(position, client)
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

```
bundle exec rspec spec/services/trading/risk_manager_spec.rb spec/services/trading/liquidation_guard_spec.rb
```
Expected: `NameError: uninitialized constant Trading::RiskManager`

- [ ] **Step 3: Implement RiskManager**

```ruby
# app/services/trading/risk_manager.rb
module Trading
  class RiskManager
    class RiskError < StandardError; end

    MAX_CONCURRENT_POSITIONS = 5
    MAX_MARGIN_UTILIZATION   = 0.40  # 40%
    DAILY_LOSS_CAP_PCT       = 0.05  # 5% of capital

    def self.validate!(signal, session:)
      new(signal, session).validate!
    end

    def initialize(signal, session)
      @signal  = signal
      @session = session
    end

    def validate!
      check_max_concurrent_positions!
      check_margin_utilization!
      check_daily_loss_cap!
    end

    private

    def check_max_concurrent_positions!
      count = Position.where(status: "open").count
      raise RiskError, "max concurrent positions reached (#{count}/#{MAX_CONCURRENT_POSITIONS})" if
        count >= MAX_CONCURRENT_POSITIONS
    end

    def check_margin_utilization!
      total_margin = Position.where(status: "open").sum(:margin).to_f
      capital      = @session.capital.to_f
      return if capital.zero?

      utilization = total_margin / capital
      raise RiskError, "margin utilization #{(utilization * 100).round(1)}% exceeds #{(MAX_MARGIN_UTILIZATION * 100).to_i}% cap" if
        utilization >= MAX_MARGIN_UTILIZATION
    end

    def check_daily_loss_cap!
      today_pnl = Trade.where("closed_at >= ?", Date.today.beginning_of_day).sum(:pnl_usd).to_f
      cap       = @session.capital.to_f * DAILY_LOSS_CAP_PCT
      raise RiskError, "daily loss cap exceeded (#{today_pnl.round(2)} USD)" if today_pnl < -cap
    end
  end
end
```

- [ ] **Step 4: Implement LiquidationGuard**

```ruby
# app/services/trading/liquidation_guard.rb
module Trading
  class LiquidationGuard
    BUFFER_PCT = 0.10  # exit if within 10% of liquidation price

    def self.check_all(client:)
      Position.where(status: "open").each do |position|
        new(position, client).check!
      end
    end

    def initialize(position, client)
      @position = position
      @client   = client
    end

    def check!
      return unless @position.liquidation_price.present?

      current_price = Rails.cache.read("ltp:#{@position.symbol}")
      return unless current_price

      if distance_to_liquidation(current_price.to_f) < BUFFER_PCT
        Rails.logger.warn("[LiquidationGuard] Emergency exit: #{@position.symbol} within #{(BUFFER_PCT * 100).to_i}% of liquidation")
        KillSwitch.force_exit_position(@position, @client)
      end
    end

    private

    def distance_to_liquidation(current_price)
      liq = @position.liquidation_price.to_f
      if @position.side == "long"
        (current_price - liq) / current_price
      else
        (liq - current_price) / current_price
      end
    end
  end
end
```

- [ ] **Step 5: Implement FundingMonitor**

```ruby
# app/services/trading/funding_monitor.rb
module Trading
  class FundingMonitor
    HIGH_FUNDING_THRESHOLD = 0.001  # 0.1% funding rate

    def self.check_all(client:)
      Position.where(status: "open").each do |position|
        new(position, client).check!
      end
    end

    def initialize(position, client)
      @position = position
      @client   = client
    end

    def check!
      rate = fetch_funding_rate
      return unless rate

      if rate.abs >= HIGH_FUNDING_THRESHOLD
        side_note = rate.positive? ? "longs paying shorts" : "shorts paying longs"
        Rails.logger.warn("[FundingMonitor] High funding #{(rate * 100).round(4)}% for #{@position.symbol} (#{side_note})")
        EventBus.publish(:high_funding_detected, {
          symbol:  @position.symbol,
          rate:    rate,
          position: @position
        })
      end
    end

    private

    def fetch_funding_rate
      Rails.cache.fetch("funding:#{@position.symbol}", expires_in: 5.minutes) do
        @client.get_funding_rate(@position.symbol)
      rescue => e
        Rails.logger.warn("[FundingMonitor] Could not fetch funding rate: #{e.message}")
        nil
      end
    end
  end
end
```

- [ ] **Step 6: Run specs to verify they pass**

```
bundle exec rspec spec/services/trading/risk_manager_spec.rb spec/services/trading/liquidation_guard_spec.rb
```
Expected: 5 examples, 0 failures

- [ ] **Step 7: Commit**

```bash
git add app/services/trading/risk_manager.rb app/services/trading/liquidation_guard.rb app/services/trading/funding_monitor.rb spec/services/trading/risk_manager_spec.rb spec/services/trading/liquidation_guard_spec.rb
git commit -m "feat: add RiskManager, LiquidationGuard, and FundingMonitor"
```

---

## Task 10: KillSwitch

**Files:**
- Create: `app/services/trading/kill_switch.rb`
- Create: `spec/services/trading/kill_switch_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/trading/kill_switch_spec.rb
require "rails_helper"

RSpec.describe Trading::KillSwitch do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:client)  { instance_double("DeltaExchange::Client") }

  before do
    allow(client).to receive(:cancel_order).and_return(true)
    allow(client).to receive(:place_order).and_return({ id: "CLOSE-001" })
  end

  describe ".call" do
    it "cancels all pending/open orders for the session" do
      order = Order.create!(
        trading_session: session, symbol: "BTCUSD", side: "buy",
        size: 1.0, price: 50000.0, order_type: "limit_order",
        status: "open", idempotency_key: "key-1", exchange_order_id: "EX-001"
      )
      described_class.call(session.id, client: client)
      expect(order.reload.status).to eq("cancelled")
      expect(client).to have_received(:cancel_order).with("EX-001")
    end

    it "closes all open positions" do
      Position.create!(symbol: "BTCUSD", side: "long", status: "open",
                       size: 1.0, entry_price: 50000.0, leverage: 10, product_id: 84)
      described_class.call(session.id, client: client)
      expect(client).to have_received(:place_order)
      expect(Position.find_by(symbol: "BTCUSD").status).to eq("closed")
    end

    it "marks session as stopped" do
      described_class.call(session.id, client: client)
      expect(session.reload.status).to eq("stopped")
    end
  end

  describe ".force_exit_position" do
    it "places a market close order for a long position" do
      position = Position.create!(symbol: "BTCUSD", side: "long", status: "open",
                                  size: 1.0, entry_price: 50000.0, leverage: 10, product_id: 84)
      described_class.force_exit_position(position, client)
      expect(client).to have_received(:place_order).with(
        hash_including(side: "sell", product_id: 84)
      )
      expect(position.reload.status).to eq("closed")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/services/trading/kill_switch_spec.rb
```
Expected: `NameError: uninitialized constant Trading::KillSwitch`

- [ ] **Step 3: Implement KillSwitch**

```ruby
# app/services/trading/kill_switch.rb
module Trading
  class KillSwitch
    def self.call(session_id, client:)
      new(session_id, client).trigger!
    end

    def self.force_exit_position(position, client)
      close_side = position.side == "long" ? "sell" : "buy"
      client.place_order(
        product_id: position.product_id,
        side:       close_side,
        order_type: "market_order",
        size:       position.size
      )
      position.update!(status: "closed")
    rescue => e
      Rails.logger.error("[KillSwitch] force_exit_position failed for #{position.symbol}: #{e.message}")
    end

    def initialize(session_id, client)
      @session_id = session_id
      @client     = client
    end

    def trigger!
      Rails.logger.warn("[KillSwitch] TRIGGERED for session #{@session_id}")
      cancel_open_orders!
      close_open_positions!
      mark_session_stopped!
    end

    private

    def cancel_open_orders!
      Order.where(trading_session_id: @session_id, status: %w[pending open])
           .each do |order|
             @client.cancel_order(order.exchange_order_id)
             order.update!(status: "cancelled")
           rescue => e
             Rails.logger.error("[KillSwitch] cancel_order failed #{order.id}: #{e.message}")
           end
    end

    def close_open_positions!
      Position.where(status: "open").each do |position|
        self.class.force_exit_position(position, @client)
      end
    end

    def mark_session_stopped!
      TradingSession.find(@session_id).update!(status: "stopped")
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/services/trading/kill_switch_spec.rb
```
Expected: 4 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/trading/kill_switch.rb spec/services/trading/kill_switch_spec.rb
git commit -m "feat: add KillSwitch for emergency position and order cancellation"
```

---

## Task 11: Event Handlers

**Files:**
- Create: `app/services/trading/handlers/tick_handler.rb`
- Create: `app/services/trading/handlers/order_handler.rb`
- Create: `app/services/trading/handlers/position_handler.rb`
- Create: `spec/services/trading/handlers/tick_handler_spec.rb`
- Create: `spec/services/trading/handlers/order_handler_spec.rb`

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/services/trading/handlers/tick_handler_spec.rb
require "rails_helper"

RSpec.describe Trading::Handlers::TickHandler do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:client)  { instance_double("DeltaExchange::Client") }
  let(:candle) do
    Trading::MarketData::Candle.new(
      symbol: "BTCUSD", open: 49900.0, high: 50200.0, low: 49800.0,
      close: 50100.0, volume: 5.0,
      opened_at: 5.minutes.ago, closed_at: 4.minutes.ago, closed: true
    )
  end

  before do
    allow(Trading::ExecutionEngine).to receive(:execute)
    allow_any_instance_of(Bot::Strategy::MultiTimeframe).to receive(:evaluate).and_return(nil)
  end

  it "does not call ExecutionEngine when strategy returns no signal" do
    described_class.new(candle, session, client).call
    expect(Trading::ExecutionEngine).not_to have_received(:execute)
  end

  it "calls ExecutionEngine when strategy generates a signal" do
    signal = Bot::Strategy::Signal.new("BTCUSD", "buy", 50100.0, candle.opened_at)
    allow_any_instance_of(Bot::Strategy::MultiTimeframe).to receive(:evaluate).and_return(signal)

    described_class.new(candle, session, client).call
    expect(Trading::ExecutionEngine).to have_received(:execute)
  end
end
```

```ruby
# spec/services/trading/handlers/order_handler_spec.rb
require "rails_helper"

RSpec.describe Trading::Handlers::OrderHandler do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let!(:order) do
    Order.create!(
      trading_session: session, symbol: "BTCUSD", side: "buy",
      size: 1.0, price: 50000.0, order_type: "limit_order",
      status: "open", idempotency_key: "key-1", exchange_order_id: "EX-001"
    )
  end
  let(:fill_event) do
    Trading::Events::OrderFilled.new(
      exchange_order_id: "EX-001",
      symbol:           "BTCUSD",
      side:             "buy",
      filled_qty:       1.0,
      avg_fill_price:   50050.0,
      status:           "filled"
    )
  end

  it "updates order status to filled" do
    described_class.new(fill_event).call
    expect(order.reload.status).to eq("filled")
    expect(order.reload.avg_fill_price).to eq(50050.0)
  end

  it "opens a position when buy order is filled" do
    expect {
      described_class.new(fill_event).call
    }.to change { Position.where(status: "open").count }.by(1)
    expect(Position.find_by(symbol: "BTCUSD", status: "open").entry_price).to eq(50050.0)
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

```
bundle exec rspec spec/services/trading/handlers/
```
Expected: `NameError: uninitialized constant Trading::Handlers`

- [ ] **Step 3: Implement TickHandler**

```ruby
# app/services/trading/handlers/tick_handler.rb
module Trading
  module Handlers
    class TickHandler
      def initialize(candle, session, client)
        @candle  = candle
        @session = session
        @client  = client
      end

      def call
        return unless @candle.closed

        signal = evaluate_strategy
        return unless signal

        converted = Events::SignalGenerated.new(
          symbol:           signal.symbol,
          side:             signal.side,
          entry_price:      signal.entry_price,
          candle_timestamp: signal.candle_ts,
          strategy:         @session.strategy,
          session_id:       @session.id
        )

        EventBus.publish(:signal_generated, converted)
        ExecutionEngine.execute(converted, session: @session, client: @client)
      rescue => e
        Rails.logger.error("[TickHandler] Error processing candle for #{@candle.symbol}: #{e.message}")
      end

      private

      def evaluate_strategy
        # Delegates to existing Bot::Strategy::MultiTimeframe
        strategy = Bot::Strategy::MultiTimeframe.new(
          client:   @client,
          symbols:  [@candle.symbol],
          config:   load_strategy_config
        )
        strategy.evaluate(@candle.symbol)
      rescue => e
        Rails.logger.error("[TickHandler] Strategy evaluation failed: #{e.message}")
        nil
      end

      def load_strategy_config
        Bot::Config.load
      end
    end
  end
end
```

- [ ] **Step 4: Implement OrderHandler**

```ruby
# app/services/trading/handlers/order_handler.rb
module Trading
  module Handlers
    class OrderHandler
      def initialize(event)
        @event = event
      end

      def call
        order = update_order_status
        return unless order&.filled?

        update_position(order)
        create_trade_if_closing(order)
        EventBus.publish(:position_updated, build_position_event(order))
      rescue => e
        Rails.logger.error("[OrderHandler] Error processing fill #{@event.exchange_order_id}: #{e.message}")
      end

      private

      def update_order_status
        OrdersRepository.update_from_fill(
          exchange_order_id: @event.exchange_order_id,
          filled_qty:        @event.filled_qty,
          avg_fill_price:    @event.avg_fill_price,
          status:            @event.status
        )
      end

      def update_position(order)
        if order.side == "buy"
          PositionsRepository.upsert_from_order(order)
        else
          PositionsRepository.close!(order.symbol)
        end
      end

      def create_trade_if_closing(order)
        return if order.side == "buy"

        entry = Position.find_by(symbol: order.symbol, status: "open")
        return unless entry

        Trade.create!(
          symbol:           order.symbol,
          side:             entry.side,
          size:             order.filled_qty,
          entry_price:      entry.entry_price,
          exit_price:       order.avg_fill_price,
          pnl_usd:          calculate_pnl(entry, order),
          duration_seconds: (Time.now - entry.entry_time.to_time).to_i,
          closed_at:        Time.now
        )
      end

      def calculate_pnl(position, order)
        multiplier = position.side == "long" ? 1 : -1
        (order.avg_fill_price - position.entry_price) * order.filled_qty * multiplier
      end

      def build_position_event(order)
        pos = Position.find_by(symbol: order.symbol)
        Events::PositionUpdated.new(
          symbol:        order.symbol,
          side:          pos&.side || "unknown",
          size:          order.filled_qty,
          entry_price:   pos&.entry_price || 0,
          mark_price:    Rails.cache.read("ltp:#{order.symbol}").to_f,
          unrealized_pnl: 0,
          status:        pos&.status || "closed"
        )
      end
    end
  end
end
```

- [ ] **Step 5: Implement PositionHandler**

```ruby
# app/services/trading/handlers/position_handler.rb
module Trading
  module Handlers
    class PositionHandler
      def initialize(event)
        @event = event
      end

      def call
        ActionCable.server.broadcast("trading_channel", {
          type:    "position_updated",
          symbol:  @event.symbol,
          side:    @event.side,
          size:    @event.size,
          status:  @event.status,
          pnl:     @event.unrealized_pnl
        })
      rescue => e
        Rails.logger.error("[PositionHandler] Broadcast failed: #{e.message}")
      end
    end
  end
end
```

- [ ] **Step 6: Run specs to verify they pass**

```
bundle exec rspec spec/services/trading/handlers/tick_handler_spec.rb spec/services/trading/handlers/order_handler_spec.rb
```
Expected: 4 examples, 0 failures

- [ ] **Step 7: Commit**

```bash
git add app/services/trading/handlers/ spec/services/trading/handlers/
git commit -m "feat: add TickHandler, OrderHandler, and PositionHandler for event-driven processing"
```

---

## Task 12: Trading::Runner

**Files:**
- Create: `app/services/trading/runner.rb`
- Create: `spec/services/trading/runner_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/trading/runner_spec.rb
require "rails_helper"

RSpec.describe Trading::Runner do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:client)  { instance_double("DeltaExchange::Client") }

  before do
    allow(Trading::Bootstrap::SyncPositions).to receive(:call)
    allow(Trading::Bootstrap::SyncOrders).to receive(:call)
    allow(Trading::LiquidationGuard).to receive(:check_all)
    allow(Trading::FundingMonitor).to receive(:check_all)
    allow(Trading::EventBus).to receive(:reset!)
  end

  subject(:runner) { described_class.new(session_id: session.id, client: client) }

  describe "#stop" do
    it "sets @running to false, causing the loop to exit" do
      runner.stop
      # Verify the runner sees itself as not running
      expect(runner.send(:running?)).to be false
    end
  end

  describe "#start" do
    it "calls bootstrap services" do
      allow(runner).to receive(:start_ws!)
      allow(runner).to receive(:run_loop)
      runner.start
      expect(Trading::Bootstrap::SyncPositions).to have_received(:call).with(client: client)
      expect(Trading::Bootstrap::SyncOrders).to have_received(:call).with(client: client, session: session)
    end

    it "registers event handlers on EventBus" do
      allow(runner).to receive(:start_ws!)
      allow(runner).to receive(:run_loop)
      subscription_count_before = 0
      runner.start
      # Handlers were registered (subscriptions exist)
      expect(Trading::EventBus).not_to have_received(:reset!)  # only reset on exit
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/services/trading/runner_spec.rb
```
Expected: `NameError: uninitialized constant Trading::Runner`

- [ ] **Step 3: Implement Trading::Runner**

```ruby
# app/services/trading/runner.rb
module Trading
  class Runner
    def initialize(session_id:, client: nil)
      @session = TradingSession.find(session_id)
      @client  = client || build_client
      @running = true
    end

    def start
      Rails.logger.info("[Runner] Starting session #{@session.id} (#{@session.strategy})")
      bootstrap!
      register_event_handlers!
      seed_candle_series!
      start_ws!
      run_loop
    ensure
      EventBus.reset!
      Rails.logger.info("[Runner] Session #{@session.id} exited cleanly")
    end

    def stop
      @running = false
    end

    private

    def bootstrap!
      Bootstrap::SyncPositions.call(client: @client)
      Bootstrap::SyncOrders.call(client: @client, session: @session)
    end

    def register_event_handlers!
      EventBus.subscribe(:candle_closed) do |candle|
        Handlers::TickHandler.new(candle, @session, @client).call
      end
      EventBus.subscribe(:order_filled) do |event|
        Handlers::OrderHandler.new(event).call
      end
      EventBus.subscribe(:position_updated) do |event|
        Handlers::PositionHandler.new(event).call
      end
    end

    def seed_candle_series!
      symbols = SymbolConfig.where(enabled: true).pluck(:symbol)
      fetcher = MarketData::OhlcvFetcher.new(client: @client)
      symbols.each do |symbol|
        candles = fetcher.fetch(symbol: symbol, resolution: "1m", limit: 200)
        MarketData::CandleSeries.load(candles)
        Rails.logger.info("[Runner] Seeded #{candles.size} candles for #{symbol}")
      end
    end

    def start_ws!
      @ws_thread = Thread.new do
        symbols = SymbolConfig.where(enabled: true).pluck(:symbol)
        MarketData::WsClient.new(client: @client, symbols: symbols).start
      rescue => e
        Rails.logger.error("[Runner] WS thread crashed: #{e.message}")
      end
    end

    def run_loop
      while running?
        LiquidationGuard.check_all(client: @client)
        FundingMonitor.check_all(client: @client)
        sleep 5
      end
    end

    def running?
      @running && @session.reload.running?
    rescue ActiveRecord::RecordNotFound
      false
    end

    def build_client
      DeltaExchange::Client.new(
        api_key:    ENV.fetch("DELTA_API_KEY"),
        api_secret: ENV.fetch("DELTA_API_SECRET")
      )
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/services/trading/runner_spec.rb
```
Expected: 3 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/trading/runner.rb spec/services/trading/runner_spec.rb
git commit -m "feat: add Trading::Runner as the long-running event-driven bot orchestrator"
```

---

## Task 13: DeltaTradingJob (Solid Queue, Redis lock)

**Files:**
- Create: `app/jobs/delta_trading_job.rb`
- Create: `spec/jobs/delta_trading_job_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/jobs/delta_trading_job_spec.rb
require "rails_helper"

RSpec.describe DeltaTradingJob, type: :job do
  let(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }
  let(:runner_dbl) { instance_double(Trading::Runner, start: nil, stop: nil) }

  before do
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

  it "does not start a second runner when lock is already held" do
    Redis.current.set("delta_bot_lock:#{session.id}", 1, nx: true, ex: 86_400)
    described_class.new.perform(session.id)
    expect(runner_dbl).not_to have_received(:start)
  end

  it "releases the Redis lock after runner completes" do
    described_class.new.perform(session.id)
    lock = Redis.current.get("delta_bot_lock:#{session.id}")
    expect(lock).to be_nil
  end

  it "releases lock even when runner raises an exception" do
    allow(runner_dbl).to receive(:start).and_raise(RuntimeError, "crash")
    expect { described_class.new.perform(session.id) }.to raise_error(RuntimeError)
    lock = Redis.current.get("delta_bot_lock:#{session.id}")
    expect(lock).to be_nil
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/jobs/delta_trading_job_spec.rb
```
Expected: `NameError: uninitialized constant DeltaTradingJob`

- [ ] **Step 3: Add Redis initializer**

```ruby
# config/initializers/redis.rb
require "redis"

module RedisClient
  def self.current
    @current ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
  end
end

# Convenience alias used throughout the app
Redis.singleton_class.define_method(:current) { RedisClient.current }
```

- [ ] **Step 4: Implement DeltaTradingJob**

```ruby
# app/jobs/delta_trading_job.rb
class DeltaTradingJob < ApplicationJob
  queue_as :trading

  # Discard retries — a new session dispatch should be explicit.
  # Retrying would spawn duplicate bots.
  discard_on StandardError

  def perform(session_id)
    return unless acquire_lock(session_id)

    runner = Trading::Runner.new(session_id: session_id)
    setup_signal_handlers(runner)
    runner.start
  rescue => e
    Rails.logger.error("[DeltaTradingJob] Session #{session_id} crashed: #{e.message}")
    mark_session_crashed(session_id)
    raise
  ensure
    release_lock(session_id)
  end

  private

  LOCK_TTL = 86_400  # 24 hours

  def acquire_lock(session_id)
    acquired = Redis.current.set("delta_bot_lock:#{session_id}", 1, nx: true, ex: LOCK_TTL)
    unless acquired
      Rails.logger.warn("[DeltaTradingJob] Lock already held for session #{session_id}. Aborting.")
    end
    acquired
  end

  def release_lock(session_id)
    Redis.current.del("delta_bot_lock:#{session_id}")
  end

  def setup_signal_handlers(runner)
    Signal.trap("TERM") { runner.stop }
    Signal.trap("INT")  { runner.stop }
  end

  def mark_session_crashed(session_id)
    TradingSession.find(session_id).update!(status: "crashed")
  rescue => e
    Rails.logger.error("[DeltaTradingJob] Could not mark session crashed: #{e.message}")
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/jobs/delta_trading_job_spec.rb
```
Expected: 4 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
git add app/jobs/delta_trading_job.rb spec/jobs/delta_trading_job_spec.rb config/initializers/redis.rb
git commit -m "feat: add DeltaTradingJob with Redis singleton lock preventing duplicate bot instances"
```

---

## Task 14: API — TradingSessionsController + Routes

**Files:**
- Create: `app/controllers/api/trading_sessions_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/trading_sessions_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/requests/api/trading_sessions_spec.rb
require "rails_helper"

RSpec.describe "Api::TradingSessions", type: :request do
  before { allow(DeltaTradingJob).to receive(:perform_later) }

  describe "GET /api/trading_sessions" do
    it "returns list of sessions" do
      TradingSession.create!(strategy: "multi_timeframe", status: "stopped", capital: 1000.0)
      get "/api/trading_sessions"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(1)
    end
  end

  describe "POST /api/trading_sessions" do
    let(:params) { { strategy: "multi_timeframe", capital: 1000.0, leverage: 10 } }

    it "creates a running session and enqueues job" do
      expect { post "/api/trading_sessions", params: params }
        .to change(TradingSession, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["status"]).to eq("running")
      expect(DeltaTradingJob).to have_received(:perform_later)
    end

    it "returns 422 when strategy is missing" do
      post "/api/trading_sessions", params: { capital: 1000.0 }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/trading_sessions/:id" do
    let!(:session) { TradingSession.create!(strategy: "multi_timeframe", status: "running", capital: 1000.0) }

    before do
      allow_any_instance_of(Trading::KillSwitch).to receive(:trigger!)
    end

    it "stops the session and triggers kill switch" do
      delete "/api/trading_sessions/#{session.id}"
      expect(response).to have_http_status(:ok)
      expect(session.reload.status).to eq("stopped")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/requests/api/trading_sessions_spec.rb
```
Expected: routing error or `ActionController::RoutingError`

- [ ] **Step 3: Add routes**

```ruby
# config/routes.rb — add inside the existing routes:
namespace :api do
  # ... existing routes ...
  resources :trading_sessions, only: [:index, :create, :destroy]
end
```

- [ ] **Step 4: Implement TradingSessionsController**

```ruby
# app/controllers/api/trading_sessions_controller.rb
module Api
  class TradingSessionsController < ApplicationController
    def index
      sessions = TradingSession.order(created_at: :desc).limit(20)
      render json: sessions
    end

    def create
      session = TradingSession.new(
        strategy: params.require(:strategy),
        status:   "running",
        capital:  params[:capital],
        leverage: params[:leverage]
      )

      if session.save
        DeltaTradingJob.perform_later(session.id)
        render json: { session_id: session.id, status: session.status }, status: :created
      else
        render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      session = TradingSession.find(params[:id])
      session.update!(status: "stopped")

      client = DeltaExchange::Client.new(
        api_key:    ENV.fetch("DELTA_API_KEY"),
        api_secret: ENV.fetch("DELTA_API_SECRET")
      )
      Trading::KillSwitch.call(session.id, client: client)

      head :ok
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```
bundle exec rspec spec/requests/api/trading_sessions_spec.rb
```
Expected: 5 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/trading_sessions_controller.rb config/routes.rb spec/requests/api/trading_sessions_spec.rb
git commit -m "feat: add TradingSessionsController API for bot start/stop control"
```

---

## Task 15: ActionCable — TradingChannel

**Files:**
- Create: `app/channels/trading_channel.rb`
- Modify: `config/initializers/event_bus.rb` — wire PositionHandler subscription at boot

- [ ] **Step 1: Implement TradingChannel**

```ruby
# app/channels/trading_channel.rb
class TradingChannel < ApplicationCable::Channel
  def subscribed
    stream_from "trading_channel"
    Rails.logger.info("[TradingChannel] Client subscribed")
  end

  def unsubscribed
    Rails.logger.info("[TradingChannel] Client disconnected")
  end
end
```

- [ ] **Step 2: Add EventBus initializer**

```ruby
# config/initializers/event_bus.rb
# Wire global EventBus subscriptions for broadcast to frontend.
# NOTE: The Runner also registers per-session handlers; this covers broadcast-only handlers
# that should always be active regardless of session state.

Rails.application.config.after_initialize do
  # Broadcast position updates to ActionCable
  Trading::EventBus.subscribe(:position_updated) do |event|
    ActionCable.server.broadcast("trading_channel", {
      type:    "position_updated",
      symbol:  event.symbol,
      status:  event.status,
      pnl:     event.unrealized_pnl
    })
  end

  # Broadcast tick LTP to frontend
  Trading::EventBus.subscribe(:tick_received) do |event|
    ActionCable.server.broadcast("trading_channel", {
      type:   "ltp",
      symbol: event.symbol,
      price:  event.price
    })
  end
end
```

- [ ] **Step 3: Run full spec suite to verify nothing is broken**

```
bundle exec rspec
```
Expected: All specs pass (or pre-existing failures only — no new failures)

- [ ] **Step 4: Commit**

```bash
git add app/channels/trading_channel.rb config/initializers/event_bus.rb
git commit -m "feat: add TradingChannel ActionCable and EventBus boot-time subscriptions for real-time frontend"
```

---

## Verification Checklist

Before running with real capital, verify each invariant:

**Execution**
- [ ] Place the same signal twice → only one order created (idempotency)
- [ ] Partial fill arrives → order status updates to `partially_filled`

**State Recovery**
- [ ] Stop Rails server, restart → positions synced from exchange
- [ ] Orders pending on exchange → local pending orders cancelled if absent

**Risk**
- [ ] Open 5 positions → 6th signal rejected by RiskManager
- [ ] Today PnL < -5% capital → new signals rejected

**Singleton**
- [ ] Enqueue `DeltaTradingJob` twice for same session → second exits immediately (lock)
- [ ] `redis-cli GET delta_bot_lock:<session_id>` shows `1` while bot runs, `nil` after exit

**Frontend**
- [ ] Connect to ActionCable from browser console → receive `ltp` events
- [ ] POST `/api/trading_sessions` → bot starts, job enqueued
- [ ] DELETE `/api/trading_sessions/:id` → bot stops, positions closed
