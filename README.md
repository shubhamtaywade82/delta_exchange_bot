# Delta Exchange Futures Bot

Automated multi-timeframe futures trading bot for Delta Exchange India.

## Strategy

- **1H** Supertrend → trend bias
- **15M** Supertrend + ADX → direction confirmation
- **5M** Supertrend flip → entry trigger
- **Trailing stop** (percentage-based) → exit

## Architecture (canonical runtime)

The **supported runtime is the Rails app under `backend/`**. It owns persistence, the JSON API, Solid Queue jobs, and `Trading::Runner` (strategy evaluation, `Trading::ExecutionEngine`, paper fills, risk).

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

If the bot ran via `DeltaTradingJob` and crashed, clear Redis:

```bash
redis-cli del "delta_bot_lock:*"
```

## Tests

**Primary suite (Rails app and trading services):**

```bash
cd backend && bundle exec rspec
```

Legacy specs at repo root `spec/` (against `lib/bot/`) are optional; CI should treat **`backend`** as the source of truth.
