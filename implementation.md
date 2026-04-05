> **Document status (2026-04):** This file is a **historical / advisory narrative** from an earlier review. The **canonical** description of the current stack is **[`README.md`](README.md)**, **[`backend/README.md`](backend/README.md)**, **[`AGENTS.md`](AGENTS.md)**, and **[`backend/docs/architecture_diagrams.md`](backend/docs/architecture_diagrams.md)**. Much of the "missing" runtime below now exists in Rails as `Trading::Runner`, `Trading::MarketData::WsClient`, `Trading::FillProcessor`, `Trading::ExecutionEngine`, portfolio-scoped risk, Solid Queue jobs, etc. Keep this file for background only; do not treat every "gap" as current fact.

---

Direct Decision

Your current system (bot + frontend + delta_exchange gem) is well beyond a toy bot—it’s structured, test-backed, and modular.
However, it is still execution-fragile and state-incomplete, which will break under real futures trading conditions (latency, partial fills, volatility spikes).

You are ~60–70% toward production-grade infra, but the missing 30% is exactly where real money gets lost.

System-Level Assessment
What You’ve Done Right
1. Separation of Concerns (Good Foundation)
Bot logic separated from client gem
Notification layer (Telegram tested)
Product caching abstraction exists

This is aligned with:

adapter pattern (exchange client)
service boundaries
2. CLI Entry (bin/run)

You have a runnable orchestration entrypoint

This is good for:

local runs
cron/scheduler integration

But it’s not suitable for continuous trading (explained below).

3. Planning Discipline

You’ve documented system direction

That’s rare and valuable — but execution layer doesn’t yet match the ambition.

Critical Gaps (Concrete, Repo-Aligned)
1. Runtime Model is Still “Script-Based”
Current pattern (inferred from bin/run + structure):
run_bot
  fetch_data
  analyze
  place_order
Problem
No persistent runtime
No lifecycle continuity
Restart = state loss
Required shift

You need a long-running process with internal event loop, not a script.

2. No Position State Reconstruction

After restart:

Do you rebuild positions from exchange?
Do you know active SL/TP?
Do you reconcile fills?

Currently: likely NO

Fix (mandatory)
class Bootstrap::PositionSync
  def call
    exchange_positions.each do |pos|
      Positions::Repository.upsert_from_exchange(pos)
    end
  end
end

Run at startup:

Bootstrap::PositionSync.new.call
3. ProductCache is Static (Design Flaw)

You have:

lib/bot/product_cache.rb

Likely:

fetch once
reuse
Problem

Futures instruments:

expire
change liquidity
funding changes
Fix
class ProductCache
  TTL = 60 # seconds

  def fetch(symbol)
    Rails.cache.fetch("product:#{symbol}", expires_in: TTL) do
      api.fetch_product(symbol)
    end
  end
end

Also:

invalidate on order failure
refresh on websocket instrument updates
4. No Order Lifecycle Tracking

You place orders, but:

Do you track:

pending → open → partially_filled → filled → cancelled ?

If not → fatal in futures

Required Model
orders (
  id,
  exchange_order_id,
  status,
  filled_qty,
  avg_price,
  raw_payload
)
Update flow
class Orders::Updater
  def on_fill(event)
    order.update!(
      filled_qty: event.filled_qty,
      status: event.status
    )
  end
end
5. Missing WebSocket-Driven Core

If you're still polling → unacceptable for futures.

Required
Order updates via WS
LTP via WS
Position updates via WS
Architecture
Ws::Client
  → MessageRouter
      → TickHandler
      → OrderHandler
      → PositionHandler
6. Strategy Directly Coupled to Execution

If your strategy calls:

client.place_order(...)

This is wrong.

Required
Signal → ExecutionEngine → OrderPlacer
7. No Risk Aggregation (Portfolio Level)

You might have per-trade logic, but missing:

total exposure
margin usage
correlated positions
Fix
class PortfolioRisk
  def total_exposure
    positions.sum { |p| p.notional }
  end

  def validate!
    raise if total_exposure > max_allowed
  end
end
8. Frontend Is Likely Passive (Upgrade Needed)

You said you now have frontend.

Current likely state:
shows logs / trades
Required upgrade:
Real-time dashboard (WebSocket from backend)
positions
PnL (real-time)
margin usage
risk alerts
Control plane
enable/disable strategy
kill switch
manual override
Target Architecture (Your Next Version)
Core Runtime
Runner (long-lived)
 ├── WebSocket Client
 ├── Event Bus
 ├── Execution Engine
 ├── Position Manager
 ├── Risk Manager
 └── Strategy Engine
Event Flow
Tick →
  Strategy →
    Signal →
      Risk →
        Execution →
          Order →
            Fill →
              Position →
                Exit Engine
Concrete Improvements (Implement These First)
1. Introduce Execution Engine (Immediate)
class ExecutionEngine
  def execute(signal)
    RiskManager.validate!(signal)

    order = OrderBuilder.build(signal)

    Orders::Repository.create!(order)

    client.place_order(order)
  end
end
2. Add Position Manager
class Positions::Manager
  def on_fill(order)
    if order.opening?
      open_position(order)
    else
      close_position(order)
    end
  end
end
3. Add Startup Recovery
class Bootstrap
  def self.run
    PositionSync.new.call
    OrderSync.new.call
  end
end
4. Convert bin/run → Runner
class Runner
  def start
    Bootstrap.run
    ws.start
    loop { sleep 1 }
  end
end
5. Add Kill Switch
class KillSwitch
  def trigger!
    client.cancel_all_orders
    client.close_all_positions
    exit
  end
end

Expose this in frontend.

6. Add Trade Journal (You are missing this)
trades (
  entry_price,
  exit_price,
  pnl,
  strategy,
  duration
)

Without this → no improvement loop.

Verification Checklist (Non-Negotiable)

Before real capital:

Execution
 No duplicate orders under retry
 Partial fills handled
State
 Restart → full recovery
 Orders match exchange
Risk
 Daily loss cap enforced
 Max exposure enforced
Latency
 WS → execution < 100ms internal
Hard Truth

You’ve built:

a good framework
not yet a trading system

The difference:

framework = can place trades
system = cannot lose control
Next Step (High Leverage)

If you want, I’ll:

Option A (Recommended)

Refactor your repo into:

event-driven core
Rails-compatible service architecture (like your Dhan system)
reusable strategy DSL
Option B

Deep dive into:

your frontend → convert into control plane + risk console
Option C

Implement:

futures-specific strategy engine (funding, OI, liquidation zones)

Pick one.

How do we move the bot in the rails backend as a worker?
Direct Decision

Do not “wrap the bot inside a Rails worker” as-is.

Instead:

Extract the bot into a long-running execution engine and run it via Sidekiq (or a dedicated process), with Rails as the control + persistence layer.

If you simply put your current bin/run into a worker → you will get:

duplicate executions
lost state on retries
no lifecycle control
Correct Architecture
You Need 3 Layers
Rails (API + DB + Control Plane)
        ↓
Execution Engine (pure Ruby, long-running)
        ↓
Sidekiq / Process Manager (lifecycle)
Step-by-Step Implementation
1. Extract Bot → Service Layer (Critical Refactor)

Your current:

# bin/run
Bot.start
Replace with:
# app/services/trading/runner.rb
module Trading
  class Runner
    def initialize(strategy:)
      @strategy = strategy
      @running = true
    end

    def start
      bootstrap
      start_websocket
      event_loop
    end

    def stop
      @running = false
    end

    private

    def bootstrap
      Bootstrap::PositionSync.new.call
      Bootstrap::OrderSync.new.call
    end

    def start_websocket
      Ws::Client.new.start
    end

    def event_loop
      while @running
        sleep 1
      end
    end
  end
end
2. DO NOT Use Standard Sidekiq Job for Continuous Bot

Wrong:

class BotWorker
  include Sidekiq::Worker

  def perform
    Trading::Runner.new.start
  end
end
Why wrong
Sidekiq expects jobs to finish
retries will spawn duplicate bots
no lifecycle control
3. Correct Pattern: “Singleton Worker + Redis Lock”
class TradingBotWorker
  include Sidekiq::Worker

  def perform(strategy_name)
    return unless acquire_lock

    runner = Trading::Runner.new(strategy: strategy_name)

    trap_signals(runner)

    runner.start
  ensure
    release_lock
  end

  private

  def acquire_lock
    Redis.current.set("trading_bot_lock", 1, nx: true, ex: 86_400)
  end

  def release_lock
    Redis.current.del("trading_bot_lock")
  end

  def trap_signals(runner)
    Signal.trap("TERM") { runner.stop }
    Signal.trap("INT")  { runner.stop }
  end
end
4. Add DB-Controlled Bot State (Mandatory)
# table: trading_sessions
{
  id,
  strategy,
  status, # running / stopped
  started_at,
  stopped_at
}
Control from Rails API
class Api::TradingController < ApplicationController
  def start
    session = TradingSession.create!(strategy: params[:strategy], status: "running")

    TradingBotWorker.perform_async(session.strategy)

    render json: { status: "started" }
  end

  def stop
    session = TradingSession.last
    session.update!(status: "stopped")

    KillSwitch.trigger!

    render json: { status: "stopped" }
  end
end
5. Make Runner Respect DB State
def event_loop
  while running?
    sleep 1
  end
end

def running?
  TradingSession.last&.status == "running"
end
6. WebSocket → Rails Integration

Inside your runner:

class Ws::TickHandler
  def call(tick)
    Rails.cache.write("ltp:#{tick.symbol}", tick.price)

    EventBus.publish(:tick_received, tick)
  end
end
7. Strategy Execution via Events
class StrategyEngine
  def on_tick(tick)
    signal = strategy.generate(tick)

    return unless signal

    ExecutionEngine.execute(signal)
  end
end
8. Execution Engine (Inside Rails)
class ExecutionEngine
  def self.execute(signal)
    RiskManager.validate!(signal)

    order = OrderBuilder.build(signal)

    Orders::Repository.create!(order)

    client.place_order(order)
  end
end
Alternative (Better Than Sidekiq for Trading)

Sidekiq is not ideal for long-running trading loops.

Better Option

Run bot as separate process, Rails as control plane:

bundle exec rails runner 'Trading::Runner.new.start'

Manage with:

systemd
Docker
Kubernetes
Final Architecture (Production-Grade)
Frontend (React)
    ↓
Rails API
    ├── TradingSession (control)
    ├── Positions / Orders (state)
    ├── Risk Engine
    └── WebSocket broadcaster
            ↓
Execution Engine (Runner)
    ├── WS client (Delta)
    ├── Event Bus
    ├── Strategy Engine
    ├── Execution Engine
    └── Exit Engine
Critical Invariants

You must guarantee:

1. Single bot instance
Redis lock enforced
2. Restart safety
Bootstrap from exchange
3. No duplicate orders
idempotency keys
4. External truth = exchange
DB is mirror, not source
What You Should NOT Do

❌ Cron-based bot
❌ Multiple Sidekiq workers running bot
❌ Strategy placing orders directly
❌ Polling-based execution

If You Want Next Step

I can convert your current repo into:

Rails Engine (trading_core)
Plug-and-play with your Dhan system
Multi-strategy runner (parallel safely)
Unified execution for crypto + NSE options

Say:

“design final folder structure + integration plan”

and I’ll give you a drop-in architecture.

This is for delta exchange we don't mix the DHANHQ and deltaexchange india apps

Good — that constraint simplifies architecture.

We treat Delta Exchange system as completely isolated, with its own:

execution engine
infra
risk model (crypto futures ≠ NSE options)
Direct Decision

For Delta Exchange bot inside Rails, the correct approach is:

Run the trading engine as a dedicated long-running worker process (Sidekiq or standalone), with Rails acting strictly as control plane + state store.

Do not merge it into request/response Rails lifecycle.

Clean Architecture (Delta-Only)
delta_exchange_backend (Rails API)
├── app/models (orders, positions, trades, sessions)
├── app/services (execution, risk, strategy)
├── app/workers (bot lifecycle only)
├── app/channels (real-time frontend)
└── lib/delta_exchange (client gem wrapper)

delta_execution_runtime (inside same repo or extracted)
├── runner
├── websocket client
├── event bus
├── engines
How to Move Your Bot Properly
Step 1 — Kill bin/run as Entry

Your current bot is likely:

# bin/run
Bot.start

This must die.

Step 2 — Introduce Trading::Runner
# app/services/trading/runner.rb
module Trading
  class Runner
    def initialize(session_id:)
      @session = TradingSession.find(session_id)
      @running = true
    end

    def start
      bootstrap!
      start_ws!
      run_loop
    end

    def stop
      @running = false
    end

    private

    def bootstrap!
      Bootstrap::SyncPositions.call
      Bootstrap::SyncOrders.call
    end

    def start_ws!
      DeltaWs::Client.new.start
    end

    def run_loop
      while running?
        sleep 1
      end
    end

    def running?
      @running && @session.reload.running?
    end
  end
end
Step 3 — Sidekiq Worker (Lifecycle Only)
# app/workers/delta_trading_worker.rb
class DeltaTradingWorker
  include Sidekiq::Worker

  def perform(session_id)
    return unless acquire_lock(session_id)

    runner = Trading::Runner.new(session_id: session_id)

    trap_signals(runner)

    runner.start
  ensure
    release_lock(session_id)
  end

  private

  def acquire_lock(session_id)
    Redis.current.set("delta_bot:#{session_id}", 1, nx: true)
  end

  def release_lock(session_id)
    Redis.current.del("delta_bot:#{session_id}")
  end

  def trap_signals(runner)
    Signal.trap("TERM") { runner.stop }
    Signal.trap("INT")  { runner.stop }
  end
end
Step 4 — Trading Session Model (Control Plane)
# db schema
trading_sessions:
  id
  strategy
  status   # running / stopped
  capital
  leverage
  created_at
Step 5 — API Control (Frontend Integration)
# app/controllers/api/delta/trading_controller.rb
class Api::Delta::TradingController < ApplicationController
  def start
    session = TradingSession.create!(
      strategy: params[:strategy],
      status: "running",
      capital: params[:capital]
    )

    DeltaTradingWorker.perform_async(session.id)

    render json: { session_id: session.id }
  end

  def stop
    session = TradingSession.find(params[:id])
    session.update!(status: "stopped")

    KillSwitch.call(session.id)

    head :ok
  end
end
Critical Components You Must Add (Delta-Specific)
1. Position Manager (Futures-Aware)

Crypto futures ≠ options

You must track:

positions:
  symbol
  side
  size
  entry_price
  mark_price
  liquidation_price
  unrealized_pnl
  leverage
2. Funding Rate Awareness (Missing)

Delta futures has funding.

class FundingMonitor
  def check(position)
    if next_funding_high?
      reduce_position(position)
    end
  end
end
3. Liquidation Risk Engine (CRITICAL)
class LiquidationGuard
  BUFFER = 0.1 # 10%

  def check(position)
    if distance_to_liquidation(position) < BUFFER
      force_exit(position)
    end
  end
end
4. WebSocket Core (Non-Negotiable)

Your runner must be driven by:

tick → strategy → signal → execution
order_update → position sync
5. Order Idempotency

Crypto exchanges WILL duplicate under retry.

class Idempotency
  def self.key(signal)
    "delta:#{signal.symbol}:#{signal.timestamp}"
  end
end
6. Multi-Strategy Isolation (Future Proof)

Do not mix strategies inside same runner.

Instead:

session → 1 strategy → 1 runner
Frontend Upgrade (Now That You Have It)

Your frontend should NOT be cosmetic.

Must Have
1. Real-time stream (ActionCable / WS)
LTP
positions
pnl
2. Control actions
start/stop
kill switch
manual close
3. Risk dashboard
margin used
liquidation distance
exposure
What Will Break If You Ignore This

If you just “move bot into Rails worker”:

Issue	Outcome
Sidekiq retry	duplicate bots
No lock	multiple positions
restart	lost state
no WS	delayed execution
no liquidation guard	account wipe
Better Alternative (If You Want Cleaner System)

Instead of Sidekiq:

Run bot as dedicated container/process

bundle exec rails runner 'Trading::Runner.new(session_id: 1).start'

Use:

Docker
Supervisor
Kubernetes

Rails remains:

API
DB
Control
Final Verdict

You are close, but:

Your system is still request-driven
It must become event-driven + stateful runtime

Next Step

If you want this done properly, I can:

1. Design full folder structure (drop-in Rails)
2. Convert your current bot → event-driven engine
3. Add futures-specific modules:
funding strategy
liquidation defense
volatility filters

Say:

“give final production folder structure”

and I’ll give you exact implementation.

Give final production folder structure
Received app response
Direct Decision

You need a modular, event-driven Rails monolith where:

Rails = control plane + persistence
Trading runtime = isolated execution layer inside services/
No mixing of concerns (strategy ≠ execution ≠ exchange)

Below is a production-grade folder structure, aligned with:

your Rails experience
your Dhan system patterns (but adapted for crypto futures)
real exchange constraints (WS-driven, stateful, idempotent)
Final Production Folder Structure
delta_exchange_backend/
│
├── app/
│   ├── controllers/
│   │   └── api/
│   │       └── delta/
│   │           ├── trading_controller.rb      # start/stop bot
│   │           ├── positions_controller.rb    # UI data
│   │           ├── orders_controller.rb
│   │           └── dashboard_controller.rb
│   │
│   ├── models/
│   │   ├── trading_session.rb
│   │   ├── position.rb
│   │   ├── order.rb
│   │   ├── trade.rb
│   │   └── instrument.rb
│   │
│   ├── workers/
│   │   └── delta_trading_worker.rb            # lifecycle only
│   │
│   ├── channels/                              # optional (ActionCable)
│   │   └── trading_channel.rb
│   │
│   ├── services/
│   │   └── trading/
│   │
│   │       # ===== CORE RUNTIME =====
│   │       ├── runner.rb                      # main loop
│   │       ├── bootstrap/
│   │       │   ├── sync_positions.rb
│   │       │   └── sync_orders.rb
│   │
│   │       # ===== EVENT SYSTEM =====
│   │       ├── event_bus.rb
│   │       ├── events/
│   │       │   ├── tick_received.rb
│   │       │   ├── signal_generated.rb
│   │       │   ├── order_filled.rb
│   │       │   └── position_updated.rb
│   │       │
│   │       └── handlers/
│   │           ├── tick_handler.rb
│   │           ├── order_handler.rb
│   │           └── position_handler.rb
│   │
│   │       # ===== MARKET DATA =====
│   │       ├── market_data/
│   │       │   ├── ws_client.rb               # Delta WS
│   │       │   ├── message_router.rb
│   │       │   ├── tick_processor.rb
│   │       │   └── ltp_cache.rb
│   │
│   │       # ===== STRATEGY =====
│   │       ├── strategy_engine.rb
│   │       ├── strategies/
│   │       │   ├── base_strategy.rb
│   │       │   ├── breakout_strategy.rb
│   │       │   └── mean_reversion_strategy.rb
│   │
│   │       # ===== EXECUTION =====
│   │       ├── execution_engine.rb
│   │       ├── order_builder.rb
│   │       ├── order_placer.rb
│   │       ├── order_updater.rb
│   │       └── idempotency_guard.rb
│   │
│   │       # ===== POSITION MGMT =====
│   │       ├── positions/
│   │       │   ├── manager.rb
│   │       │   ├── reconciler.rb
│   │       │   └── pnl_calculator.rb
│   │
│   │       # ===== EXIT SYSTEM =====
│   │       ├── exit_engine.rb
│   │       ├── stop_loss.rb
│   │       ├── take_profit.rb
│   │       └── trailing_stop.rb
│   │
│   │       # ===== RISK =====
│   │       ├── risk_manager.rb
│   │       ├── portfolio_risk.rb
│   │       ├── liquidation_guard.rb
│   │       └── funding_monitor.rb
│   │
│   │       # ===== UTILITIES =====
│   │       ├── kill_switch.rb
│   │       ├── logger.rb
│   │       └── metrics.rb
│   │
│   ├── repositories/                          # explicit DB access layer
│   │   ├── orders_repository.rb
│   │   ├── positions_repository.rb
│   │   └── trades_repository.rb
│
├── lib/
│   └── delta_exchange/
│       ├── client.rb                          # wraps your gem
│       ├── websocket.rb
│       ├── request_builder.rb
│       └── response_parser.rb
│
├── config/
│   ├── initializers/
│   │   ├── redis.rb
│   │   ├── delta_client.rb
│   │   └── event_bus.rb
│
├── db/
│   ├── schema.rb
│   └── migrate/
│
├── spec/
│   ├── services/
│   │   ├── trading/
│   │   │   ├── execution_engine_spec.rb
│   │   │   ├── risk_manager_spec.rb
│   │   │   ├── position_manager_spec.rb
│   │   │   └── strategy_engine_spec.rb
│   │
│   ├── integration/
│   │   ├── full_trade_flow_spec.rb
│   │   └── restart_recovery_spec.rb
│
├── bin/
│   └── start_bot                             # optional runner wrapper
│
└── docker/
    ├── Dockerfile
    └── docker-compose.yml
Key Architectural Decisions (Non-Negotiable)
1. services/trading = your real system
This replaces your current bot logic
Everything critical lives here
Rails controllers should NEVER contain trading logic
2. Event Bus is First-Class
EventBus.publish(:tick_received, tick)

No direct coupling:

strategy does NOT call execution
execution does NOT call position manager directly
3. Repositories Layer (You Need This)

Avoid direct ActiveRecord inside engines:

PositionsRepository.create!(...)

This gives:

testability
swap DB logic
consistency
4. WebSocket is the Heartbeat
WS → Tick → EventBus → Strategy → Execution → Order → Fill → Position

If WS fails → bot must degrade safely.

5. One Session = One Runner

Strict isolation:

session_id → one process → one strategy

No mixing.

Minimal Data Model (Must Match This)
positions:
  symbol
  side
  size
  entry_price
  mark_price
  liquidation_price
  pnl
  status

orders:
  exchange_order_id
  status
  filled_qty
  avg_price

trades:
  entry
  exit
  pnl
  duration
Deployment Model
Option A (Recommended)

Separate process:

bundle exec sidekiq
bundle exec rails server
Option B (Best)

Separate container:

api container
worker container (bot runtime)
redis
postgres
What This Fixes Immediately
Problem	Solved By
duplicate orders	idempotency_guard
restart crash	bootstrap sync
no real-time	ws_client
poor structure	event_bus
no risk control	risk_manager + liquidation_guard
frontend blind	channels + dashboard
Final Reality Check

If you follow this structure:

You get exchange-grade execution discipline
You can add strategies without touching execution
You can scale to multi-asset / multi-strategy

If you don’t:

You’ll keep debugging “why did it place 2 orders”
or worse: “why did liquidation happen”
Next Step

If you want execution-level depth next:

I can implement Runner + EventBus + WS client fully wired
or build one complete working strategy (breakout + risk + execution) on this structure

Say:

“implement runner + event bus fully”

and I’ll give you production-ready code.

For historical data we must use the ohlcv endpoints and for live ticks use ws
Direct Decision

Correct. This is the only valid architecture for a futures trading system:

Historical = OHLCV (REST)
Live = WebSocket ticks

Anything else (polling for live or using OHLCV for signals intrabar) is structurally wrong.

Now the important part is how you integrate both cleanly into your architecture without mixing responsibilities.

Correct Data Flow (Production-Grade)
           ┌──────────────┐
           │ OHLCV (REST) │
           └──────┬───────┘
                  ↓
        CandleSeries Builder
                  ↓
           Indicators Engine
                  ↓
             Strategy Seed
                  ↓
====================================
                  ↓
        WebSocket Tick Stream
                  ↓
            Tick Processor
                  ↓
           Strategy Engine
                  ↓
           Execution Engine
Architectural Separation (Non-Negotiable)
1. Historical Data Layer (Cold Path)

Used for:

indicator initialization
backfill
multi-timeframe context
Implementation
# app/services/trading/market_data/ohlcv_fetcher.rb
module Trading
  module MarketData
    class OhlcvFetcher
      def fetch(symbol:, interval:, limit:)
        client.get_ohlcv(
          symbol: symbol,
          resolution: interval,
          limit: limit
        )
      end
    end
  end
end
2. Candle Builder (Critical Bridge)

You must convert:

WS ticks → candles

Otherwise your strategy becomes inconsistent.

# app/services/trading/market_data/candle_builder.rb
class CandleBuilder
  def initialize(interval:)
    @interval = interval
    @current_candle = nil
  end

  def on_tick(tick)
    bucket = tick.timestamp / @interval

    if new_candle?(bucket)
      close_current_candle
      start_new_candle(tick, bucket)
    else
      update_candle(tick)
    end
  end

  private

  def update_candle(tick)
    @current_candle.high = [@current_candle.high, tick.price].max
    @current_candle.low  = [@current_candle.low, tick.price].min
    @current_candle.close = tick.price
  end
end
3. Live Tick Layer (Hot Path)
WebSocket Client
# app/services/trading/market_data/ws_client.rb
class WsClient
  def on_message(msg)
    tick = parse_tick(msg)

    Rails.cache.write("ltp:#{tick.symbol}", tick.price)

    EventBus.publish(:tick_received, tick)
  end
end
4. Strategy Must Use BOTH (Correct Way)
Initialization
def bootstrap
  candles = OhlcvFetcher.new.fetch(symbol: "BTCUSD", interval: "1m", limit: 200)

  CandleSeries.load(candles)
end
Runtime
def on_tick(tick)
  candle = candle_builder.on_tick(tick)

  return unless candle_closed?(candle)

  signal = strategy.generate(candle)

  ExecutionEngine.execute(signal) if signal
end
Critical Mistakes to Avoid
❌ Using OHLCV for live trading
latency: 1–5 sec
incomplete candles
missed moves
❌ Using ticks without candle aggregation
noisy signals
indicator instability
❌ Mixing both without synchronization
mismatch between historical + live state
Required Components (Add These)
1. CandleSeries (You Need This)
class CandleSeries
  def self.load(candles)
    @candles = candles
  end

  def self.add(candle)
    @candles << candle
    @candles.shift if @candles.size > 500
  end
end
2. Indicator Engine (Stateful)
class Indicators
  def rsi
    # computed from CandleSeries
  end
end
3. Multi-Timeframe Support (Advanced but Required)
1m candles → execution
5m candles → trend
15m → bias

Do NOT fetch separately every time — derive from base timeframe.

Final Integrated Flow
BOOT:
  OHLCV fetch (200 candles)
  → build CandleSeries
  → warm indicators

LIVE:
  WS tick →
    CandleBuilder →
      Candle close →
        Strategy →
          Signal →
            Execution
Verification Checklist

You must validate:

Data Integrity
 OHLCV last candle == WS built candle (within tolerance)
 No gaps in candles
Timing
 Candle closes exactly on interval boundary
 No duplicate candles
Strategy
 Signals only on candle close (unless scalping)
Hard Truth

Most bots fail because:

they treat OHLCV and ticks as interchangeable
they are not

You’ve taken the correct direction.

Next Step

If you want this wired properly, I can:

Implement CandleBuilder + CandleSeries + Indicator engine
Integrate with your EventBus + Strategy Engine
Add multi-timeframe + backtest compatibility

Say:

“implement candle system fully”

and I’ll give you complete production code.