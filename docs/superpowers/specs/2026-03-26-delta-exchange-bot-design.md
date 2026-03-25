# Delta Exchange Futures Trading Bot — Design Spec

**Date:** 2026-03-26
**Status:** Approved

---

## Overview

A standalone Ruby automated futures trading bot for Delta Exchange India. Trades multiple crypto perpetual futures using a multi-timeframe (MTF) Supertrend + ADX strategy with percentage-based trailing stop exits. All monetary values displayed to the user in INR (1 USD = 85 INR, configurable). Supports dry-run, testnet, and live trading modes.

---

## Goals

- Trade multiple crypto perpetual futures (BTCUSDT, ETHUSDT, SOLUSDT, etc.) automatically
- Use MTF confluence (1H trend → 15M confirm → 5M entry) for high-confidence signals
- Risk-based position sizing using available capital and configured leverage
- Percentage-based trailing stop exits
- Real-time LTP via WebSocket for trailing stop monitoring
- OHLCV data via REST API for indicator calculations
- All user-facing monetary values in INR
- Telegram alerts + structured JSON file logging
- Dry-run, testnet, and live modes
- Robust crash recovery via supervisor with auto-restart

---

## Project Structure

```
delta_exchange_bot/
├── bin/
│   └── run                        # Entry point — boots supervisor
├── config/
│   ├── bot.yml                    # Main config (symbols, timeframes, strategy params)
│   └── .env.example               # API keys template
├── lib/
│   ├── bot/
│   │   ├── supervisor.rb          # Thread lifecycle manager, crash recovery
│   │   ├── config.rb              # Loads & validates bot.yml, exposes typed config
│   │   ├── product_cache.rb       # Startup cache: symbol → {product_id, contract_value}
│   │   │
│   │   ├── feed/
│   │   │   ├── websocket_feed.rb  # Wraps delta_exchange WebSocket, streams LTP ticks
│   │   │   └── price_store.rb     # Thread-safe in-memory LTP store per symbol (Mutex)
│   │   │
│   │   ├── strategy/
│   │   │   ├── multi_timeframe.rb # MTF confluence: 1H trend → 15M confirm → 5M entry
│   │   │   ├── supertrend.rb      # Supertrend indicator (ATR-based, Wilder's)
│   │   │   ├── adx.rb             # ADX/DI indicator (Wilder's smoothing)
│   │   │   └── signal.rb          # Signal value object (symbol, side, price, candle_ts)
│   │   │
│   │   ├── execution/
│   │   │   ├── order_manager.rb   # Places/cancels orders via delta_exchange gem
│   │   │   ├── position_tracker.rb# Thread-safe open position state (Mutex-protected)
│   │   │   └── risk_calculator.rb # Position sizing: capital × risk% / trail% → lots
│   │   │
│   │   ├── account/
│   │   │   └── capital_manager.rb # Fetches USDT available_balance, converts to INR
│   │   │
│   │   └── notifications/
│   │       ├── telegram_notifier.rb
│   │       └── logger.rb          # Structured JSON line logger
├── spec/                          # RSpec tests
├── logs/                          # bot.log output
├── Gemfile
├── .env.example
└── README.md
```

---

## Architecture

### Threading Model

Four threads managed by the Supervisor:

| Thread | Responsibility | Restart on crash |
|---|---|---|
| WebSocket thread | Streams LTP ticks via EventMachine → updates PriceStore | Yes |
| Strategy thread | Runs every 5 minutes — fetches OHLCV via REST, evaluates MTF signals, triggers orders | Yes |
| Trailing stop thread | Polls PriceStore every 15s — updates peak price, triggers exit if stop hit | Yes |
| Main / Supervisor | Monitors all threads, handles SIGINT/SIGTERM gracefully | N/A |

**Thread safety:**
- `PriceStore` — protected by a `Mutex`; written by WebSocket thread, read by Trailing Stop thread
- `PositionTracker` — protected by a `Mutex`; written by OrderManager (Strategy thread), read and written by Trailing Stop thread. All public methods acquire the mutex before accessing internal state.
- `ProductCache` — written once at startup before threads are spawned; read-only thereafter (no mutex required)

### EventMachine Ownership

The `delta_exchange` WebSocket client runs EventMachine in a dedicated background thread via `Connection#start`. The Supervisor owns this thread reference. On shutdown, the Supervisor calls `ws_feed.stop` which calls `connection.stop` → `EM.stop if EM.reactor_running?` from within the EM thread via `EM.schedule` to avoid cross-thread EM calls. The Supervisor then joins the EM thread with a 5-second timeout before proceeding to exit.

### Data Sources

- **OHLCV candles**: `client.market_data.candles({ "symbol" => symbol, "resolution" => resolution, "start" => start_ts, "end" => end_ts })` — REST API, fetched each strategy cycle. Note: pass as a plain hash with string keys; avoid `end:` as a Ruby keyword argument.
- **Live LTP**: `DeltaExchange::Websocket::Client` subscribing to `v2/ticker` channel — WebSocket feed

### Product Cache (startup)

At startup, before any threads are spawned, the bot fetches all configured symbols from the REST API and builds a `ProductCache` mapping:

```
symbol → { product_id: Integer, contract_value: Float, contract_type: String }
```

This cache is used by `OrderManager` (needs `product_id` for order placement) and `RiskCalculator` (needs `contract_value` for lot sizing). The cache builds **both** a forward index (`symbol → attrs`) and an inverse index (`product_id → symbol`) at startup so that restart reconciliation can map `Position.product_id` back to a symbol string efficiently. If any configured symbol cannot be resolved at startup, the bot logs an error, sends a Telegram alert, and exits rather than starting with a broken config.

---

## Configuration (`config/bot.yml`)

```yaml
mode: testnet                       # dry_run | testnet | live

strategy:
  supertrend:
    atr_period: 10
    multiplier: 3.0
  adx:
    period: 14
    threshold: 25                   # minimum ADX for trend confirmation
  trailing_stop_pct: 1.5            # percent from peak price
  timeframes:
    trend: "60"                     # 1H in minutes (Delta Exchange resolution param)
    confirm: "15"                   # 15M
    entry: "5"                      # 5M
  candles_lookback: 100             # number of candles to fetch per timeframe
  min_candles_required: 30          # minimum candles needed before computing indicators

risk:
  risk_per_trade_pct: 1.5           # % of available capital risked per trade (max 10)
  max_concurrent_positions: 5
  max_margin_per_position_pct: 40   # cap margin deployed per position at 40% of available capital
  usd_to_inr_rate: 85.0             # fallback rate

symbols:
  - symbol: BTCUSDT
    leverage: 10
  - symbol: ETHUSDT
    leverage: 15
  - symbol: SOLUSDT
    leverage: 20

notifications:
  telegram:
    enabled: true
    bot_token: <%= ENV['TELEGRAM_BOT_TOKEN'] %>
    chat_id: <%= ENV['TELEGRAM_CHAT_ID'] %>
  daily_summary_time: "18:00"       # 24h clock, IST (TZ=Asia/Kolkata required in env)

logging:
  level: info                       # debug | info | warn | error
  file: logs/bot.log
```

### Config Validation Rules (`config.rb`)

Required fields and valid ranges enforced at startup — bot exits on invalid config:

| Field | Type | Valid values |
|---|---|---|
| `mode` | String | `dry_run`, `testnet`, `live` |
| `strategy.supertrend.atr_period` | Integer | 1–50 |
| `strategy.supertrend.multiplier` | Float | 0.5–10.0 |
| `strategy.adx.period` | Integer | 1–50 |
| `strategy.adx.threshold` | Integer | 10–50 |
| `strategy.trailing_stop_pct` | Float | 0.1–20.0 |
| `strategy.candles_lookback` | Integer | 50–500 |
| `strategy.min_candles_required` | Integer | >= atr_period + adx_period |
| `risk.risk_per_trade_pct` | Float | 0.1–10.0 |
| `risk.max_concurrent_positions` | Integer | 1–20 |
| `risk.max_margin_per_position_pct` | Float | 5–100 |
| `risk.usd_to_inr_rate` | Float | > 0 |
| `symbols` | Array | non-empty, each has `symbol` (String) and `leverage` (Integer 1–200) |
| `notifications.daily_summary_time` | String | HH:MM format |

---

## Strategy Logic

### Multi-Timeframe Confluence

**LONG entry — ALL must be true:**
1. 1H Supertrend → BULLISH (close above supertrend line)
2. 15M Supertrend → BULLISH AND ADX > threshold
3. 5M Supertrend → just flipped BULLISH on the **latest closed candle** (candle timestamp > last_acted_candle_ts for this symbol)

**SHORT entry — ALL must be true:**
1. 1H Supertrend → BEARISH (close below supertrend line)
2. 15M Supertrend → BEARISH AND ADX > threshold
3. 5M Supertrend → just flipped BEARISH on the **latest closed candle** (candle timestamp > last_acted_candle_ts for this symbol)

**"Just flipped" definition:** The second-to-last candle had direction X, the last closed candle has direction Y (opposite). The candle's `timestamp` must be strictly greater than `last_acted_candle_ts[symbol]` stored in `MultiTimeframe`. On signal emission, `last_acted_candle_ts[symbol]` is updated to the triggering candle's timestamp. This prevents re-firing the same flip on subsequent strategy cycles.

**Skip conditions:**
- Open position already exists for this symbol (checked via PositionTracker)
- Concurrent positions >= `max_concurrent_positions`
- ADX < threshold on 15M (ranging market)
- Candles returned < `min_candles_required` for any timeframe → skip symbol this cycle, log warning
- Calculated position size rounds to zero lots (insufficient capital)

### Supertrend (Wilder's ATR, standard carry-forward implementation)

```
# Initialisation (first bar):
atr[0]    = high[0] - low[0]
upper[0]  = (high[0] + low[0]) / 2 + multiplier × atr[0]
lower[0]  = (high[0] + low[0]) / 2 - multiplier × atr[0]
direction[0] = BULLISH

# Each subsequent bar i:
tr[i]   = max(high[i] - low[i], |high[i] - close[i-1]|, |low[i] - close[i-1]|)
atr[i]  = (atr[i-1] × (period - 1) + tr[i]) / period   # Wilder's smoothing

basic_upper[i] = (high[i] + low[i]) / 2 + multiplier × atr[i]
basic_lower[i] = (high[i] + low[i]) / 2 - multiplier × atr[i]

# Band carry-forward (prevents band from moving away from price):
upper[i] = basic_upper[i] < upper[i-1] || close[i-1] > upper[i-1] ? basic_upper[i] : upper[i-1]
lower[i] = basic_lower[i] > lower[i-1] || close[i-1] < lower[i-1] ? basic_lower[i] : lower[i-1]

# Direction:
if direction[i-1] == BEARISH && close[i] > upper[i-1]
  direction[i] = BULLISH
elsif direction[i-1] == BULLISH && close[i] < lower[i-1]
  direction[i] = BEARISH
else
  direction[i] = direction[i-1]

supertrend_line[i] = direction[i] == BULLISH ? lower[i] : upper[i]
```

Default: ATR period = 10, multiplier = 3.0. Minimum bars needed = `atr_period + 1`.

### ADX (Wilder's smoothing)

```
# For each bar i (requires i >= 1):
up_move   = high[i] - high[i-1]
down_move = low[i-1] - low[i]

plus_dm[i]  = up_move > down_move && up_move > 0 ? up_move : 0
minus_dm[i] = down_move > up_move && down_move > 0 ? down_move : 0

tr[i] = max(high[i]-low[i], |high[i]-close[i-1]|, |low[i]-close[i-1]|)

# Wilder's smoothing (initialised as sum of first `period` values):
smoothed_tr[i]       = smoothed_tr[i-1] - (smoothed_tr[i-1] / period) + tr[i]
smoothed_plus_dm[i]  = smoothed_plus_dm[i-1] - (smoothed_plus_dm[i-1] / period) + plus_dm[i]
smoothed_minus_dm[i] = smoothed_minus_dm[i-1] - (smoothed_minus_dm[i-1] / period) + minus_dm[i]

plus_di[i]  = 100 × smoothed_plus_dm[i] / smoothed_tr[i]
minus_di[i] = 100 × smoothed_minus_dm[i] / smoothed_tr[i]
dx[i]       = 100 × |plus_di[i] - minus_di[i]| / (plus_di[i] + minus_di[i])

# ADX is Wilder's smoothed average of DX:
adx[i] = (adx[i-1] × (period - 1) + dx[i]) / period
```

Default: period = 14, threshold = 25. Minimum bars needed = `period × 2`.

### Trailing Stop

```
On entry (LONG):
  peak_price  = fill_price
  stop_price  = fill_price × (1 - trail_pct / 100)
  entry_time  = Time.now.utc

Each LTP poll (LONG):
  if ltp > peak_price
    peak_price = ltp
    stop_price = peak_price × (1 - trail_pct / 100)
  if ltp <= stop_price → trigger exit

On entry (SHORT):
  peak_price  = fill_price
  stop_price  = fill_price × (1 + trail_pct / 100)
  entry_time  = Time.now.utc

Each LTP poll (SHORT):
  if ltp < peak_price
    peak_price = ltp
    stop_price = peak_price × (1 + trail_pct / 100)
  if ltp >= stop_price → trigger exit
```

Default: trail_pct = 1.5%

---

## Risk & Position Sizing

Delta Exchange uses **integer contract lots** for `size` in orders (not fractional BTC). Each product has a `contract_value` (e.g. 0.001 BTC per lot for BTCUSDT). All sizing is computed in lots.

```
# Capital
# WalletBalance.find_by_asset calls .all and finds by asset_symbol — confirmed present in gem
available_usdt  = WalletBalance.find_by_asset('USDT').available_balance  # use available_balance, not balance
capital_inr     = available_usdt × usd_to_inr_rate

# Risk
risk_inr        = capital_inr × (risk_per_trade_pct / 100)
risk_usd        = risk_inr / usd_to_inr_rate

# Position sizing
contract_value  = ProductCache[symbol][:contract_value]     # e.g. 0.001 BTC
trail_distance  = entry_price_usd × (trail_pct / 100)       # loss per BTC if stop hit
loss_per_lot    = trail_distance × contract_value           # loss per contract lot
raw_lots        = risk_usd / loss_per_lot
leveraged_lots  = raw_lots × leverage
final_lots      = leveraged_lots.floor                      # Integer, no partial lots
```

**Guards:**
- `final_lots == 0` → skip, log "insufficient capital for minimum position"
- Margin check: `(final_lots × contract_value × entry_price_usd) / leverage > available_usdt × (max_margin_per_position_pct / 100)` → cap `final_lots` to the maximum that fits within the margin cap
- Concurrent positions >= `max_concurrent_positions` → skip
- Symbol already has open position → skip

**Example (BTCUSDT, $45,000, 10x leverage, 1.5% risk, 1.5% trail, contract_value=0.001 BTC):**
```
available_usdt = 500
capital_inr    = 500 × 85  = ₹42,500
risk_inr       = ₹42,500 × 1.5%  = ₹637.5
risk_usd       = ₹637.5 / 85     = $7.5
trail_distance = $45,000 × 1.5%  = $675
loss_per_lot   = $675 × 0.001    = $0.675
raw_lots       = $7.5 / $0.675   = 11.1
leveraged_lots = 11.1 × 10       = 111
final_lots     = 111 (integer)

Notional = 111 × 0.001 × $45,000 = $4,995
Margin   = $4,995 / 10            = $499.5  (within 40% cap: 500 × 40% = $200 → cap applies)
Capped   = floor(200 × 10 / (0.001 × 45000)) = floor(200/4.5) = 44 lots

Telegram: "Opened LONG BTCUSDT | 44 lots | ~0.044 BTC | Entry: $45,000 (₹38,25,000)"
```

---

## Execution Modes

| Mode | Order placement | Candle fetch | WebSocket LTP |
|---|---|---|---|
| `dry_run` | Simulated locally, no API calls | Real REST (production) | Real WebSocket (production) |
| `testnet` | Delta Exchange testnet API | Testnet REST | Testnet WebSocket |
| `live` | Delta Exchange production API | Production REST | Production WebSocket |

Mode is set via `config/bot.yml` `mode:` key or `BOT_MODE` env var (env var takes precedence).

**Dry-run simulated fill price:** The simulated entry price is the latest LTP from `PriceStore` at the moment the signal is processed. If LTP is not yet available (WebSocket not connected), the strategy loop skips this cycle and logs a warning.

---

## Notifications

### Telegram Messages

```
Trade opened (LONG):
  🟢 LONG BTCUSDT opened
  Entry: $45,000 (₹38,25,000) | 44 lots (~0.044 BTC)
  Leverage: 10x | Margin: ₹16,830 ($198)
  Risk: ₹637 | Trail Stop: $44,325 (₹37,67,625)
  [DRY RUN] appended if mode is dry_run

Trade closed (trail stop):
  🔴 BTCUSDT closed — Trail Stop Hit
  Exit: $45,800 (₹38,93,000)
  PnL: +$35.2 (+₹2,992)
  Duration: 2h 15m

Error / crash:
  ⚠️ Bot error in StrategyThread: [message]
  Supervisor restarting in 5s... (attempt 2/5)

Circuit breaker:
  🛑 StrategyThread crashed 5 times in 10 minutes. Bot halted. Manual restart required.

Daily summary (sent at daily_summary_time IST):
  📊 Daily Summary — 26 Mar 2026
  Trades: 4 | Wins: 3 | Losses: 1
  Gross PnL: +₹18,200
  Balance: ₹44,700 ($526)
```

### Log Format (JSON lines → `logs/bot.log`)

```json
{"ts":"2026-03-26T10:15:00Z","level":"info","event":"trade_opened","symbol":"BTCUSDT","side":"long","entry_usd":45000,"entry_inr":3825000,"lots":44,"leverage":10,"risk_inr":637,"stop_usd":44325,"mode":"testnet"}
{"ts":"2026-03-26T12:30:00Z","level":"info","event":"trade_closed","symbol":"BTCUSDT","exit_usd":45800,"pnl_usd":35.2,"pnl_inr":2992,"reason":"trail_stop","duration_seconds":8100}
```

---

## Supervisor & Crash Recovery

```
Thread crash → log error → Telegram alert → exponential backoff restart
Backoff: 5s → 10s → 30s → 60s (capped at 60s)

Circuit breaker: if a thread crashes >= 5 times within a 10-minute window:
  → Send Telegram "Bot halted" alert
  → Stop all threads cleanly
  → Exit 1 (do not auto-restart)

SIGINT / SIGTERM (graceful shutdown):
  1. Stop strategy loop (finish current cycle or skip)
  2. Stop trailing stop monitor
  3. Signal EM thread to stop WebSocket via EM.schedule { EM.stop }
  4. Join EM thread (5s timeout)
  5. Flush logs
  6. Exit 0
  (Open positions are left as-is — user manages them manually after shutdown)

On bot restart with existing open positions:
  1. Call Position.all via API → returns positions with product_id
  2. For each position: look up symbol via ProductCache (product_id → symbol)
  3. Filter to only positions whose symbol is in config symbols list
     (ignore manually-opened positions on unconfigured symbols)
  4. Re-adopt into PositionTracker: set entry_price = mark_price (current),
     peak_price = mark_price, entry_time = Time.now.utc (actual entry time unknown)
  5. Log "re-adopted N open positions from API" + Telegram alert
  6. Note: trailing stop restarts from current mark_price — not original entry
```

---

## Rate Limit Handling

The strategy thread fetches N symbols × 3 timeframes = up to 3N REST calls per cycle. If `DeltaExchange::RateLimitError` is raised, the strategy thread catches it, sleeps for `e.retry_after_seconds`, then retries the failed symbol. Failed symbols are skipped for the current cycle (not retried infinitely) if a second rate limit error occurs.

---

## Dependencies (Gemfile)

```ruby
gem 'delta_exchange', path: '../delta_exchange'   # local gem
gem 'dotenv'                                       # ENV loading from .env
gem 'telegram-bot-ruby'                            # Telegram notifications
gem 'tzinfo'                                       # Timezone handling for daily summary IST
gem 'rspec', group: :test
gem 'rspec-mocks', group: :test
```

`TZ=Asia/Kolkata` must be set in the environment (`.env` file) for daily summary timing to work correctly.

No Rails. No database. No Redis. Pure in-memory state — kept simple intentionally.

---

## Testing Strategy

- Unit tests for `Supertrend` — known OHLCV fixtures, assert direction and supertrend line matches TradingView reference values
- Unit tests for `ADX` — known fixtures, assert +DI, -DI, ADX values within 0.01 tolerance
- Unit tests for `RiskCalculator` — assert lot sizing formula, margin cap guard, zero-lot guard
- Unit tests for `MultiTimeframe` — stub candle data with known directions, assert signal output and `last_acted_candle_ts` update
- Unit tests for `PositionTracker` — assert trailing stop update logic, thread safety (concurrent read/write with Mutex)
- Integration test for `OrderManager` in dry-run mode — assert no API calls made, positions recorded in PositionTracker
- Unit tests for `Config` — assert validation rules reject invalid configs
- No mocking of `delta_exchange` gem internals — test at the boundary

---

## Out of Scope (v1)

- Web dashboard / UI
- Database persistence of trade history
- Options trading
- Multiple simultaneous entries per symbol
- Live leverage auto-adjustment based on volatility
- Backtesting engine
- Live USD/INR rate fetching (hardcoded fallback rate used)
