# Delta Exchange Futures Bot

Automated multi-timeframe futures trading bot for Delta Exchange India.

## Strategy

Configured under `strategy.timeframes` in `backend/config/bot.yml` (overridable via DB `Setting` keys where supported). **Defaults in repo YAML:**

- **4h** Supertrend → trend bias  
- **1h** Supertrend + ADX → direction confirmation  
- **5m** Supertrend → entry trigger  

**Trailing stop** (percentage-based) → exit. Adaptive / ML Supertrend variant and other strategy keys live in the same YAML section.

## Architecture (canonical runtime)

The **supported runtime is the Rails app under `backend/`**. It owns persistence, the JSON API, Solid Queue jobs, and `Trading::Runner` (strategy evaluation, `Trading::ExecutionEngine`, paper fills, risk).

For visual maps of runtime interactions and per-component internal data flows, see [`backend/docs/architecture_diagrams.md`](backend/docs/architecture_diagrams.md). SMC / analysis Telegram behavior (scheduled digest vs tick-driven event alerts) is summarized in [`backend/docs/smc_event_alerts.md`](backend/docs/smc_event_alerts.md).

- **Repo root `lib/bot/`** duplicates older standalone code paths. Prefer `backend/app/services/bot/` and `backend/app/services/trading/`. Root **`bin/run` delegates to `backend/bin/bot`** so you do not need two different entry commands.
- **Process model:** Run **at most one** long-lived trading loop per machine (or per Redis lock namespace) for a given session. `Trading::EventBus` is global in-process state; `Trading::Runner#start` resets subscribers on exit. A WebSocket consumer runs in a **background thread** inside the same process as the runner; size the Active Record pool accordingly if you add more threads.

### Starting the bot in production (choose one pattern)

1. **Dedicated process (recommended for clarity)**  
   Run `backend/bin/bot` under systemd, supervisord, or your orchestrator (same as Procfile `bot:`). It uses `Trading::Runner` by default; set `LEGACY_BOT_RUNNER=1` only if you must use `Bot::Runner`.

2. **Solid Queue job**  
   Creating a trading session via the API enqueues `DeltaTradingJob`, which acquires `delta_bot_lock:<session_id>` in Redis and runs the same `Trading::Runner`. Use a **worker pool dedicated to the `:trading` queue** (concurrency 1 per session) so long-running work does not starve other jobs. The job uses `discard_on StandardError` — restarts are explicit (new session / ops), not silent retries.

Do **not** run `bin/bot` and `DeltaTradingJob` for the **same** session concurrently; the lock prevents double dispatch from the job side, but duplicate operators can still start extra processes.

## Setup

```bash
cp .env.example .env
# Fill in DELTA_API_KEY, DELTA_API_SECRET, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
cd backend && bundle install
```

Root `Gemfile` exists for legacy `spec/` against `lib/bot/` only. Day-to-day work uses **`backend/Gemfile`**.

## Configuration

Edit `config/bot.yml` (or `backend/config/bot.yml` — keep them aligned if you use both):

- Set `mode: dry_run` to paper trade (no orders placed)
- Set `mode: testnet` to trade on Delta Exchange testnet
- Set `mode: live` for live trading

### Telegram (default `Trading::Runner`)

`LEGACY_BOT_RUNNER=1` (`Bot::Runner`) has always supported Telegram. **`Trading::Runner`** (default `backend/bin/bot` and `./bin/dev`) uses the same notifier: `Bot::Config.load` builds config from **defaults**, then **`backend/config/bot.yml`** (only keys that overlap the runtime shape), then **Settings** from the DB (same keys as `db/seeds.rb`), then environment fallbacks below.

1. In **Admin → Settings** (or SQL), set:
   - `notifications.telegram.enabled` = `true` (boolean)
   - `notifications.telegram.bot_token` = token from [@BotFather](https://t.me/BotFather)
   - `notifications.telegram.chat_id` = your chat or group id (numeric string)
2. Optionally toggle event keys: `notifications.telegram.events.signals`, `.positions`, `.trailing`, `.status`, `.errors`, `.analysis` (booleans). When **`.analysis`** is `true`:
   - **`Trading::AnalysisDashboardRefreshJob`** (Solid Queue, default **every 15 minutes** in `backend/config/recurring.yml`) sends each symbol’s Ollama **`ai_insight`** to Telegram in chunked messages.
   - **`Trading::Analysis::SmcAlertEvaluator`** (wired from **`Trading::Runner`** on each **`tick_received`**) can send **SMC confluence event** messages (rising-edge alerts + optional Ollama follow-up). Details, Redis keys, and env toggles: [`backend/docs/smc_event_alerts.md`](backend/docs/smc_event_alerts.md).
3. Restart **`bin/bot`** (or the process running `Trading::Runner`) so config is picked up. For digest pushes, ensure **`bin/jobs`** (Solid Queue) is running so the refresh job executes. **SMC event alerts require the runner process** (they are not triggered by the digest job alone).

**Precedence:** a value in Settings overrides `bot.yml`. If `bot_token` or `chat_id` is still blank after that, `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` from the environment are applied. If `TELEGRAM_ENABLED` is set in the environment, it forces `notifications.telegram.enabled` on or off (`1` / `true` / `yes` / `on` vs anything else).

Seeds default **`notifications.telegram.enabled` to `false`**, so nothing is sent until you enable it via Settings, `backend/config/bot.yml`, or `TELEGRAM_ENABLED`. API send failures from `Trading::Runner` are logged to **Rails.logger** (and stderr if no logger is passed).

## Usage

### Development (all services)

Backend (Rails), bot process, Solid Queue worker, and frontend (Vite):

```bash
./bin/dev
```

**Default bot process (`backend/bin/bot`):** `Trading::Runner` with **paper execution** when Bot mode is `dry_run` (or `EXECUTION_MODE=paper`): real **ticker + orderbook** from Delta Exchange India, **no** private orders/fills WebSocket, simulated fills via `ExecutionEngine` (portfolio/risk/order/fill pipeline in the DB). Set `EXECUTION_MODE=live` and Bot `live` mode only for real order placement. Set `LEGACY_BOT_RUNNER=1` to use the older `Bot::Runner` only.

### Production / single bot process

```bash
TZ=Asia/Kolkata ./bin/run
```

(`./bin/run` changes into `backend/` and runs `bin/bot`.)

## API access control

If the JSON API is reachable beyond a trusted network, set **`API_ACCESS_TOKEN`** in the backend environment (see `backend/.env.example`). When set, every `ApplicationController` request must send the same value as either:

- `Authorization: Bearer <token>`, or  
- `X-Api-Token: <token>`

When unset, authentication is not enforced (local development default). **Action Cable** is not covered by this mechanism; restrict WebSocket exposure separately if needed.

## Fresh start (trades + documented Redis/cache)

Use one command when you want an empty **trade history**, **order/fill chain**, **positions**, **signals**, **strategy learning rows**, and a **defined Redis + cache reset** so auto-calibration (e.g. `AiRefinementJob`, adaptive cache) starts from a clean slate.

**Stop the bot and `bin/jobs` (or any worker running `Trading::Runner` / `DeltaTradingJob`) before running this**, so nothing writes while you wipe state.

```bash
cd backend
CONFIRM=YES bin/rails trading:fresh_start
```

### What it deletes (PostgreSQL)

- `portfolio_ledger_entries`, `fills`, `orders` (after clearing `orders.position_id`)
- `trades`
- `generated_signals`, `positions`
- `strategy_params` (online-learning parameters; they repopulate as new trades close)

It does **not** delete `trading_sessions`, `portfolios`, `settings`, `symbol_configs`, or Solid Queue data.

### Redis scope (`Redis.current`, logical DB from `REDIS_URL`)

The Redis **database index** is the path segment in `REDIS_URL` (e.g. `redis://localhost:6379/1` → DB `1`). Keep this aligned with `config.cache_store` in each environment so app Redis keys and Rails cache see the same logical DB where intended (`backend/config/initializers/redis.rb`).

Exact keys removed:

- `delta:positions:live`, `delta:wallet:state`, `delta:execution:incidents`, `delta:strategy:state`
- `learning:ai_refinement:enqueue_lock`, `delta_bot_session_resumer:boot_lock`

`SCAN` + `DEL` for every key matching:

- `delta_bot_lock:*` (session locks)
- `delta:order:*` (signal idempotency keys)
- `delta_bot:prices:*` (legacy price store prefix)
- `delta:smc_alert:*` (SMC Telegram event-alert state, gate, and cooldown keys)

### Cache scope (`Rails.cache`)

- **`Rails.cache.clear`** — in development/production this is the Redis cache store (often DB `1` in `config/environments/development.rb`), namespaced per environment. This drops **LTP/mark**, **`adaptive:*`**, **`runtime_config:*`**, **`ai:edge:*`**, **`learning:metrics:*`**, **`funding:*`**, **`delta:product:lot_multiplier:*`**, and other keys written only through Rails cache.

Implementation: [`Trading::FreshStart`](backend/app/services/trading/fresh_start.rb), task `trading:fresh_start` in [`backend/lib/tasks/trading_reset.rake`](backend/lib/tasks/trading_reset.rake).

For a **lighter** reset (positions + signals only, no trades), use `CONFIRM=YES bin/rails trading:reset_positions_and_signals`.

## Stopping & restarting

### Normal stop

If the app was started in the foreground (e.g. `./bin/dev`), press **Ctrl+C** so foreman stops all processes.

### Force stop

```bash
pkill -9 -f "bin/bot" || true
pkill -9 -f "rails" || true
pkill -9 -f "puma" || true
pkill -9 -f "npm run dev" || true

rm -f backend/tmp/pids/server.pid
```

### Clearing locks

If the bot ran via `DeltaTradingJob` and crashed, clear session locks (Redis `SCAN`, since `DEL` does not expand globs):

```bash
redis-cli --scan --pattern 'delta_bot_lock:*' | xargs -r redis-cli del
```

Or run a full documented reset (includes locks): `CONFIRM=YES bin/rails trading:fresh_start` (see **Fresh start** above).

## Tests

**Primary suite (Rails app and trading services):**

```bash
cd backend && bundle exec rspec
```

Legacy specs at repo root `spec/` (against `lib/bot/`) are optional; treat **`backend`** as the source of truth.

## CI/CD

GitHub Actions live under [`.github/workflows/`](.github/workflows/). See [`.github/README.md`](.github/README.md) for required checks, the `delta_exchange` path gem variable, and optional Kamal deploy.
