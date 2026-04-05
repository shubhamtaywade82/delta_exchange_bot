# SMC event alerts (Telegram)

Event-driven Telegram notifications when Smart Money Concepts (SMC) confluence conditions **cross from false to true** on the configured **entry** timeframe. This path is **separate from** the scheduled **15-minute** `Trading::AnalysisDashboardRefreshJob` digest (which can also push Ollama text to Telegram).

**Non-goals:** These alerts do **not** open or close positions. They are read-only notifications.

---

## How it runs

1. **`Trading::Runner`** starts **`Trading::MarketData::WsClient`**, which subscribes to Delta **`v2/ticker`** (and other streams).
2. On each ticker message, **`WsClient#handle_tick`** writes **`Rails.cache`** keys **`ltp:<symbol>`** and **`mark:<symbol>`**, then publishes **`Trading::Events::TickReceived`** via **`Trading::EventBus`** (`:tick_received`).
3. The runner registers **`Trading::Analysis::SmcAlertTickSubscriber`** on **`tick_received`**, which calls **`Trading::Analysis::SmcAlertEvaluator.call(symbol: ...)`**.

So **WebSocket ticks** are the wake-up signal. **Evaluation** still uses **REST OHLCV** (same as the analysis digest), not raw tick math.

---

## What gets computed

For each evaluation (when allowed by the gate — see below), the evaluator:

- Fetches candles for **`strategy.timeframes.trend`**, **`confirm`**, and **`entry`** via **`Trading::Analysis::HistoricalCandles`**.
- Builds **`Trading::Analysis::SmcConfluenceMtf`**, which runs **`Trading::Analysis::SmcConfluence::Engine`** per timeframe (Pine-parity confluence logic in `smc_confluence/engine.rb`).
- Reads **alert booleans** from the **entry** timeframe’s **`timeframes[<entry>]["confluence"]`** hash (last bar in the returned series — includes Delta’s **current forming bar** when present in the payload).

Mapped alert ids (rising-edge monitored):

| Id | Meaning (summary) |
|----|-------------------|
| `long_signal` / `short_signal` | Engine long/short signal |
| `high_conviction_long` / `high_conviction_short` | Same as base signal with **score ≥ 5** |
| `liq_sweep_bull` / `liq_sweep_bear` | Sell-side / buy-side liquidity sweep flags |
| `choch_bull` / `choch_bear` | CHOCH flags |
| `pdh_sweep` / `pdl_sweep` | Previous day high/low sweep flags (exposed on `BarResult`) |

Optional **Ollama** synthesis uses the **same payload shape as the dashboard digest** (structure, `smc_by_timeframe`, `smc_confluence_mtf`, `trade_plan`) via **`Trading::Analysis::DigestBuilder.ai_synthesis_from_loaded_candles`**, then **`Trading::Analysis::AiSmcSynthesizer`**. That runs **at most once per evaluation burst** (multiple edges in one pass share one AI call).

---

## Telegram

- **Event message:** **`Bot::Notifications::TelegramNotifier#notify_smc_confluence_event`** — short header (bell), symbol, optional TF line, condition line, optional **Close** from **`ltp:<symbol>`** cache.
- **AI follow-up:** If enabled, chunked messages labeled **`AI (SMC EVENT)`** (same chunking idea as **`notify_smc_analysis_digest`**).

**Required settings (DB / `bot.yml` merged into `Bot::Config`):**

- `notifications.telegram.enabled` and valid token/chat_id
- **`notifications.telegram.events.analysis`** must be **true** (same flag as the 15m digest AI push)

Implementation bridge: **`Trading::TelegramNotifications`**.

---

## Redis keys (`Redis.current`, same logical DB as `REDIS_URL`)

| Key pattern | Purpose |
|-------------|---------|
| `delta:smc_alert:prev:<symbol>` | JSON map of last known alert booleans (for **rising-edge** detection). |
| `delta:smc_alert:gate:<symbol>` | Short TTL **throttle** between evaluation attempts (not every tick hits REST/Ollama). |
| `delta:smc_alert:cooldown:<symbol>:<alert_id>` | Per-alert **cooldown** after a send (reduces flicker on forming bars). |

**Bootstrap:** The first successful evaluation for a symbol **writes `prev` and sends no Telegram** so existing “already true” flags do not spam on first contact.

**Fresh start:** `Trading::FreshStart` scans and deletes **`delta:smc_alert:*`** (along with other trading keys).

---

## Environment variables

| Variable | Default | Effect |
|----------|---------|--------|
| `ANALYSIS_SMC_ALERT_ENABLED` | on (anything except `false`) | Master kill switch for the event path. |
| `ANALYSIS_SMC_ALERT_INCLUDE_AI` | on (anything except `false`) | When off, no Ollama call for event bursts. |
| `ANALYSIS_SMC_ALERT_MIN_INTERVAL_S` | `15` | TTL for **`gate`** — minimum seconds between eval attempts per symbol. |
| `ANALYSIS_SMC_ALERT_COOLDOWN_S` | `300` | TTL for **`cooldown:<symbol>:<alert_id>`** after sending that alert. |

Ollama timeouts and model URL follow the same **`Ai::OllamaClient`** / **`OLLAMA_*`** settings as the digest job.

---

## Code map

| Piece | Location |
|-------|----------|
| Tick subscription | `app/services/trading/runner.rb` (`SmcAlertTickSubscriber`) |
| Subscriber wrapper | `app/services/trading/analysis/smc_alert_tick_subscriber.rb` |
| Core logic | `app/services/trading/analysis/smc_alert_evaluator.rb` |
| WS → LTP cache + `EventBus` | `app/services/trading/market_data/ws_client.rb` |
| Digest-equivalent AI bundle | `app/services/trading/analysis/digest_builder.rb` (`ai_synthesis_from_loaded_candles`) |
| Telegram | `app/services/bot/notifications/telegram_notifier.rb` |
| Confluence engine | `app/services/trading/analysis/smc_confluence/engine.rb`, `bar_result.rb` |
| Scheduled digest (comparison) | `app/jobs/trading/analysis_dashboard_refresh_job.rb`, `config/recurring.yml` |

---

## How to verify behavior

1. **Runner + WebSocket:** Alerts only run while **`Trading::Runner`** is running (the only in-app starter of **`WsClient`** in this repo).
2. **Symbol:** **`SymbolConfig`** row for the symbol must be **enabled**.
3. **Expect no message on first eval** for a symbol (bootstrap `prev` only).
4. **Rising edge:** A condition must flip **false → true** vs stored `prev`; if it stays true, you only get one edge until it goes false and true again.
5. **Inspect Redis:** `KEYS delta:smc_alert:*` (or `SCAN`) — gate TTL, cooldown keys, `prev` JSON.
6. **Dev tuning:** Lower **`ANALYSIS_SMC_ALERT_MIN_INTERVAL_S`** and **`ANALYSIS_SMC_ALERT_COOLDOWN_S`** to see repeats faster; clear `delta:smc_alert:*` for a symbol to re-bootstrap.
7. **Console (careful):** `Trading::Analysis::SmcAlertEvaluator.call(symbol: "BTCUSD")` still respects **gate**; clear **`delta:smc_alert:gate:<symbol>`** between rapid manual calls if testing.

---

## Relationship to the 15-minute digest

| Aspect | Event alerts | `AnalysisDashboardRefreshJob` |
|--------|----------------|------------------------------|
| Trigger | Throttled **`tick_received`** | Solid Queue **`every 15 minutes`** |
| Telegram | Short event (+ optional AI once per burst) | Chunked **`SMC ANALYSIS`** from digest `ai_insight` |
| Redis dashboard | No | Writes **`delta:analysis:dashboard`** |
| Execution | No | No |

Both can use **Ollama**; both respect **`notifications.telegram.events.analysis`** when sending analysis-style Telegram content.
