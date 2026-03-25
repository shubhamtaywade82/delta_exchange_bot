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
│   │   │
│   │   ├── feed/
│   │   │   ├── websocket_feed.rb  # Wraps delta_exchange WebSocket, streams LTP ticks
│   │   │   └── price_store.rb     # Thread-safe in-memory LTP store per symbol
│   │   │
│   │   ├── strategy/
│   │   │   ├── multi_timeframe.rb # MTF confluence: 1H trend → 15M confirm → 5M entry
│   │   │   ├── supertrend.rb      # Supertrend indicator (ATR-based)
│   │   │   ├── adx.rb             # ADX/DI indicator
│   │   │   └── signal.rb          # Signal value object (symbol, side, price, strength)
│   │   │
│   │   ├── execution/
│   │   │   ├── order_manager.rb   # Places/cancels orders via delta_exchange gem
│   │   │   ├── position_tracker.rb# Tracks open positions, trailing stop state
│   │   │   └── risk_calculator.rb # Position sizing: capital × risk% / trail% → qty
│   │   │
│   │   ├── account/
│   │   │   └── capital_manager.rb # Fetches USDT balance, converts to INR
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

### Data Sources

- **OHLCV candles**: `DeltaExchange::Client.new.market_data.candles(symbol:, resolution:, start:, end:)` — REST API, fetched each strategy cycle
- **Live LTP**: `DeltaExchange::Websocket::Client` subscribing to `v2/ticker` channel — WebSocket feed

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
    trend: "60"                     # 1H — sets overall bias
    confirm: "15"                   # 15M — Supertrend + ADX confirmation
    entry: "5"                      # 5M — entry trigger (Supertrend flip)
  candles_lookback: 100             # number of candles to fetch per timeframe

risk:
  risk_per_trade_pct: 1.5           # % of capital risked per trade
  max_concurrent_positions: 5
  max_capital_per_position_pct: 40  # cap single position at 40% of capital
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
  daily_summary_time: "18:00"       # IST

logging:
  level: info                       # debug | info | warn | error
  file: logs/bot.log
```

---

## Strategy Logic

### Multi-Timeframe Confluence

**LONG entry — ALL must be true:**
1. 1H Supertrend → BULLISH (close above supertrend line)
2. 15M Supertrend → BULLISH AND ADX > threshold
3. 5M Supertrend → just flipped BULLISH (fresh signal on latest closed candle)

**SHORT entry — ALL must be true:**
1. 1H Supertrend → BEARISH (close below supertrend line)
2. 15M Supertrend → BEARISH AND ADX > threshold
3. 5M Supertrend → just flipped BEARISH (fresh signal on latest closed candle)

**Skip conditions:**
- Open position already exists for this symbol
- Concurrent positions >= `max_concurrent_positions`
- ADX < threshold on 15M (ranging market)
- Calculated position size rounds to zero (insufficient capital)

### Supertrend

```
ATR(period) over high/low/close
upper_band = (high + low) / 2 + multiplier × ATR
lower_band = (high + low) / 2 - multiplier × ATR
Direction flips BULLISH when close crosses above upper_band
Direction flips BEARISH when close crosses below lower_band
```

Default: ATR period = 10, multiplier = 3.0

### ADX

```
+DM, -DM computed from high/low
Smoothed over period (Wilder's smoothing)
ADX = 100 × EMA(|+DI - -DI| / (+DI + -DI))
```

Default: period = 14, threshold = 25

### Trailing Stop

```
On entry (LONG):
  peak_price  = entry_price
  stop_price  = entry_price × (1 - trail_pct / 100)

Each LTP tick (LONG):
  if ltp > peak_price → peak_price = ltp
  stop_price = peak_price × (1 - trail_pct / 100)
  if ltp <= stop_price → trigger exit

On entry (SHORT):
  peak_price  = entry_price
  stop_price  = entry_price × (1 + trail_pct / 100)

Each LTP tick (SHORT):
  if ltp < peak_price → peak_price = ltp
  stop_price = peak_price × (1 + trail_pct / 100)
  if ltp >= stop_price → trigger exit
```

Default: trail_pct = 1.5%

---

## Risk & Position Sizing

```
capital_inr       = wallet_usdt_balance × usd_to_inr_rate
risk_inr          = capital_inr × (risk_per_trade_pct / 100)
risk_usd          = risk_inr / usd_to_inr_rate

trail_distance    = entry_price_usd × (trail_pct / 100)
raw_qty           = risk_usd / trail_distance
leveraged_qty     = raw_qty × leverage
final_qty         = floor(leveraged_qty / contract_value) × contract_value
```

**Guards:**
- `final_qty == 0` → skip, log "insufficient capital for minimum position"
- `final_qty × entry_price_usd > capital_usd × max_capital_per_position_pct / 100` → cap to limit
- Concurrent positions >= max → skip
- Symbol already has open position → skip

**Example (BTCUSDT, $45,000, 10x leverage, 1.5% risk, 1.5% trail):**
```
capital_inr    = 500 × 85 = ₹42,500
risk_inr       = ₹42,500 × 1.5% = ₹637.5
risk_usd       = ₹637.5 / 85 = $7.5
trail_distance = $45,000 × 1.5% = $675
raw_qty        = $7.5 / $675 = 0.0111 BTC
leveraged_qty  = 0.0111 × 10 = 0.111 BTC
```

---

## Execution Modes

| Mode | Order placement | Candle fetch | WebSocket LTP |
|---|---|---|---|
| `dry_run` | Simulated locally, no API | Real (REST) | Real (WebSocket) |
| `testnet` | Delta Exchange testnet API | Testnet REST | Testnet WebSocket |
| `live` | Delta Exchange production API | Production REST | Production WebSocket |

Mode is set via `config/bot.yml` `mode:` key or `BOT_MODE` env var.

---

## Notifications

### Telegram Messages

```
Trade opened (LONG):
  🟢 LONG BTCUSDT opened
  Entry: $45,000 (₹38,25,000)
  Qty: 0.11 | Leverage: 10x
  Risk: ₹637 | Trail Stop: $44,325 (₹37,67,625)

Trade closed (trail stop):
  🔴 BTCUSDT closed — Trail Stop Hit
  Exit: $45,800 | PnL: +$88 (+₹7,480)
  Duration: 2h 15m

Error / crash:
  ⚠️ Bot error in StrategyThread: [message]
  Supervisor restarting in 5s...

Daily summary:
  📊 Daily Summary — 26 Mar 2026
  Trades: 4 | Wins: 3 | Losses: 1
  Gross PnL: +₹18,200
  Balance: ₹44,700 ($526)
```

### Log Format (JSON lines → `logs/bot.log`)

```json
{"ts":"2026-03-26T10:15:00Z","level":"info","event":"trade_opened","symbol":"BTCUSDT","side":"long","entry_usd":45000,"entry_inr":3825000,"qty":0.11,"leverage":10,"risk_inr":637,"stop_usd":44325}
{"ts":"2026-03-26T12:30:00Z","level":"info","event":"trade_closed","symbol":"BTCUSDT","exit_usd":45800,"pnl_usd":88,"pnl_inr":7480,"reason":"trail_stop"}
```

---

## Supervisor & Crash Recovery

```
Thread crash → log error → Telegram alert → exponential backoff restart
Backoff: 5s → 10s → 30s → 60s (capped)

SIGINT / SIGTERM:
  1. Stop strategy loop
  2. Stop trailing stop monitor (leave open positions as-is)
  3. Close WebSocket connection
  4. Flush logs
  5. Exit 0

On bot restart with existing open positions:
  - Call Position.all via API
  - Re-adopt any open positions into PositionTracker
  - Recalculate trailing stop from current mark_price as new peak
```

---

## Dependencies (Gemfile)

```ruby
gem 'delta_exchange', path: '../delta_exchange'   # local gem
gem 'dotenv'                                       # ENV loading from .env
gem 'faraday'                                      # HTTP (used by gem internally)
gem 'telegram-bot-ruby'                            # Telegram notifications
gem 'rspec'                                        # Testing
```

No Rails. No database. No Redis. Pure in-memory state — kept simple intentionally.

---

## Testing Strategy

- Unit tests for `Supertrend`, `ADX`, `RiskCalculator` — pure functions, no API calls
- Unit tests for `MultiTimeframe` — stub candle data, assert signal output
- Unit tests for `PositionTracker` — assert trailing stop update/trigger logic
- Integration test for `OrderManager` in dry-run mode — assert no API calls made
- No mocking of `delta_exchange` gem internals — test at the boundary

---

## Out of Scope (v1)

- Web dashboard / UI
- Database persistence of trade history
- Options trading
- Multiple simultaneous entries per symbol
- Live leverage auto-adjustment based on volatility
- Backtesting engine
