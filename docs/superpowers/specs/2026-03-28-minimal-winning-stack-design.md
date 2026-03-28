# Minimal Winning Stack — Design Spec

**Date:** 2026-03-28
**Status:** Approved
**Branch:** rails

---

## Overview

Extend the existing Supertrend+ADX multi-timeframe strategy with a production-grade signal stack for Delta Exchange perpetual futures. The goal is higher-quality entries (fewer whipsaws) by adding derivatives-aware filters and replacing the noisy 5M Supertrend flip with BOS + Order Block entry logic.

This is **not a replacement** — it is a surgical extension. The 1H/15M Supertrend+ADX regime filter stays. Only the 5M entry trigger and the post-signal confirmation layer change.

---

## Signal Flow

```
1H Supertrend (macro bias)
  + 15M Supertrend + ADX > threshold (regime confirmation)
  ↓ both aligned?

5M Break of Structure (BOS) confirmed
  + price at / near fresh Order Block zone
  ↓ entry triggered?

MomentumFilter   → RSI not extreme (block long if RSI > 70, short if RSI < 30)
VolumeFilter     → CVD direction agrees + price on correct side of VWAP
DerivativesFilter → OI rising (no divergence) + funding rate within ±0.05%
  ↓ all three pass?

Signal fired → OrderManager (unchanged downstream)
```

Filters are **veto-only** — they block signals but never generate them. Each filter returns `{passed: bool, reason: string}` for logging and UI display.

---

## Architecture

### Approach

Approach B — Indicator modules + filter pipeline. Each indicator is a standalone module (same pattern as existing `Supertrend` and `ADX`). Filters are a separate layer. `MultiTimeframe` orchestrates but does not compute.

### Layer Map

```
lib/bot/
  strategy/
    indicators/
      rsi.rb              # RSI(14) from candles
      vwap.rb             # VWAP + deviation bands from candles
      bos.rb              # Break of Structure detector from candles
      order_block.rb      # Order Block zone finder from candles
    filters/
      momentum_filter.rb  # RSI gate
      volume_filter.rb    # CVD + VWAP gate
      derivatives_filter.rb # OI divergence + funding rate threshold

  feed/
    cvd_store.rb          # Accumulates buy/sell volume from all_trades WS
    derivatives_store.rb  # OI (v2/tickers REST, polled 30s) + funding_rate WS

backend/app/
  services/bot/strategy/
    indicators/           # Mirror of lib/bot/strategy/indicators/ (for historical analysis)
    filters/              # Mirror of lib/bot/strategy/filters/
  controllers/api/
    order_blocks_controller.rb  # GET /api/symbols/:symbol/order_blocks

frontend/
  Signal Quality Panel    # Per-symbol filter verdict display
  Order Block Zones       # Chart overlay (horizontal rectangle bands)
  Derivatives Strip       # OI trend + funding rate badge per symbol
```

---

## New Components

### Indicators (lib/bot/strategy/indicators/)

#### rsi.rb
- Input: candles array, period (default 14)
- Output: `{value: Float, overbought: bool, oversold: bool}`
- Algorithm: Wilder's smoothing of average gain/loss

#### vwap.rb
- Input: candles array (requires volume field)
- Output: `{vwap: Float, deviation_pct: Float, price_above: bool}`
- Algorithm: cumulative (price × volume) / cumulative volume, reset per session

#### bos.rb
- Input: candles array (5M timeframe)
- Output: `{direction: :bullish|:bearish, level: Float, confirmed: bool}`
- Algorithm: detect swing high/low, confirm when close breaks the level
- Bullish BOS: close breaks above most recent swing high
- Bearish BOS: close breaks below most recent swing low

#### order_block.rb
- Input: candles array
- Output: `[{side: :bull|:bear, high: Float, low: Float, fresh: bool, strength: Float}]`
- Algorithm: identify last down-candle before a bullish impulse (bull OB) and last up-candle before bearish impulse (bear OB)
- `fresh`: OB has not been fully mitigated by price trading through it

---

### Data Stores (lib/bot/feed/)

#### cvd_store.rb
- Subscribes to `all_trades` WebSocket channel per symbol
- Accumulates: `buy_volume += size` when side=buy, `sell_volume += size` when side=sell
- Exposes: `{cumulative_delta: Float, delta_trend: :bullish|:bearish|:neutral}`
- Trend determined by delta direction over rolling window (configurable, default 50 trades)
- Thread-safe (Mutex, same pattern as PriceStore)

#### derivatives_store.rb
- **Funding Rate**: subscribes to `funding_rate` WebSocket channel
- **Open Interest**: polls `GET /v2/tickers/:symbol` every 30s (via background thread)
- OI trend: compares current OI to previous sample — rising/falling
- Exposes: `{oi_usd: Float, oi_trend: :rising|:falling, funding_rate: Float, funding_extreme: bool}`
- `funding_extreme`: true if |funding_rate| > 0.05%
- Thread-safe (Mutex)

---

### Filters (lib/bot/strategy/filters/)

Each filter takes signal side (`:long`/`:short`), relevant store/indicator data, and returns `{passed: bool, reason: String}`.

#### momentum_filter.rb
- Block long if RSI > 70 (overbought)
- Block short if RSI < 30 (oversold)
- Pass otherwise

#### volume_filter.rb
- CVD check: `cvd_trend` must match signal side (bullish for long, bearish for short)
- VWAP check: price above VWAP for longs, below for shorts
- Both conditions must pass

#### derivatives_filter.rb
- OI check: `oi_trend` must be `:rising` (falling OI = divergence = potential trap)
- Funding check: `funding_extreme` must be false
- Both conditions must pass

---

## Modified Files

### lib/bot/strategy/multi_timeframe.rb
**Change:** Replace 5M Supertrend flip detection with BOS + Order Block check.

Old entry logic:
```ruby
m5_flip = m5_prev[:direction] != m5_current[:direction]
```

New entry logic:
```ruby
bos = Indicators::Bos.compute(m5_candles)
obs = Indicators::OrderBlock.compute(m5_candles)
entry = bos[:confirmed] &&
        bos[:direction] == overall_direction &&
        obs.any? { |ob| ob[:side] == signal_side && ob[:fresh] }
```

After entry triggers, run filter chain:
```ruby
filters = [
  Filters::MomentumFilter.check(side, rsi),
  Filters::VolumeFilter.check(side, cvd_store, current_price, vwap),
  Filters::DerivativesFilter.check(derivatives_store)
]
return nil if filters.any? { |f| !f[:passed] }
```

### lib/bot/feed/websocket_feed.rb
**Change:** Add subscriptions for `all_trades` and `funding_rate` channels. Route messages to `CvdStore` and `DerivativesStore` respectively.

### lib/bot/persistence/state_publisher.rb
**Change:** Extend Redis payload with new indicator state:
```ruby
{
  # existing fields unchanged...
  rsi: Float,
  vwap: Float,
  vwap_deviation_pct: Float,
  bos_direction: String,
  bos_level: Float,
  order_blocks: Array,
  cvd_trend: String,
  cvd_delta: Float,
  oi_usd: Float,
  oi_trend: String,
  funding_rate: Float,
  funding_extreme: Boolean,
  filters: {
    momentum:    {passed: Boolean, reason: String},
    volume:      {passed: Boolean, reason: String},
    derivatives: {passed: Boolean, reason: String}
  }
}
```

---

## Backend (Rails)

### Mirror Services
`backend/app/services/bot/strategy/indicators/` and `filters/` mirror the bot modules. Used for historical analysis and dashboard display — not live trading.

### New Endpoint
`GET /api/symbols/:symbol/order_blocks`
Returns array of current OB zones for chart overlay.
Source: latest Redis state for the symbol, extracts `order_blocks` field.

### Existing Endpoints (no changes needed)
`GET /api/strategy_status` — already reads from Redis, automatically includes new fields in response payload.

---

## Frontend (React)

### Signal Quality Panel
Per-symbol card section showing:
- Trend layer: 1H/15M direction badges + ADX value
- Entry layer: BOS direction + level price
- RSI row: value + pass/fail badge
- CVD row: trend direction + delta value + pass/fail
- VWAP row: price vs VWAP + pass/fail
- OI row: USD value + trend arrow + pass/fail
- Funding Rate row: percentage + extreme flag + pass/fail
- Summary row: all-pass → "SIGNAL FIRED" (green) or first failure reason (red)

### Order Block Zones
Horizontal rectangle overlay on price chart (if candlestick chart exists):
- Bull OBs: green band (high/low of zone)
- Bear OBs: red band
- Faded opacity if `fresh: false`
- Data from `/api/symbols/:symbol/order_blocks`

### Derivatives Strip
Compact row below each symbol showing:
- OI trend arrow (▲/▼) + USD value
- Funding rate badge — green if normal, amber if extreme

---

## Configuration (config/bot.yml additions)

```yaml
strategy:
  # existing supertrend/adx config unchanged...

  rsi:
    period: 14
    overbought: 70
    oversold: 30

  vwap:
    session_reset: true   # reset VWAP at UTC 00:00 daily (crypto has no session open)

  bos:
    swing_lookback: 10    # candles to look back for swing high/low

  order_block:
    min_impulse_pct: 0.3  # minimum move % to qualify as impulse
    max_ob_age: 20        # candles before OB considered stale

  filters:
    funding_rate_threshold: 0.05   # % — block if |rate| exceeds this
    cvd_window: 50                 # trades to measure CVD trend over

  derivatives:
    oi_poll_interval: 30  # seconds between OI REST fetches
```

---

## Data Flow Summary

```
WS: all_trades    → CvdStore      ─┐
WS: funding_rate  → DerivativesStore ─┤
REST: v2/tickers  → DerivativesStore ─┤
REST: v2/candles  → MultiTimeframe   ─┤
                                      ↓
                              MultiTimeframe.evaluate()
                                ├─ Supertrend 1H/15M (regime)
                                ├─ ADX 15M (strength)
                                ├─ BOS + OB 5M (entry)
                                ├─ RSI (momentum gate)
                                ├─ CVD + VWAP (volume gate)
                                └─ OI + Funding (derivatives gate)
                                      ↓
                              Signal (or nil if any gate fails)
                                      ↓
                              OrderManager → execution (unchanged)
                                      ↓
                              StatePublisher → Redis
                                      ↓
                              Rails API → Frontend
```

---

## Testing Plan

- Unit tests for each new indicator module (fixture candle data)
- Unit tests for each filter (mock store inputs, assert pass/fail + reason)
- Unit tests for CvdStore (simulate trade messages, verify delta accumulation)
- Unit tests for DerivativesStore (mock WS + REST responses)
- Integration test for MultiTimeframe with all components wired (dry-run mode)
- Existing Supertrend + ADX tests remain unchanged

---

## Out of Scope

- Adaptive RSI (standard period-14 RSI only for now)
- Footprint charts / full order book depth
- Liquidation level detection
- Volume Profile / Market Profile
- Any indicator beyond the Minimal Winning Stack
