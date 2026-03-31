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

## Usage

### Development (All Services)
To start the backend (Rails), the trading bot, the job worker (Solid Queue — AI refinement & scheduled jobs), and the frontend (Vite) concurrently:

```bash
./bin/dev
```

**Default bot process (`backend/bin/bot`):** `Trading::Runner` with **paper execution** when Bot mode is `dry_run` (or `EXECUTION_MODE=paper`): real **ticker + orderbook** from Delta Exchange India, **no** private orders/fills WebSocket, simulated fills via `ExecutionEngine` (portfolio/risk/order/fill pipeline in the DB). Set `EXECUTION_MODE=live` and Bot `live` mode only for real order placement. Set `LEGACY_BOT_RUNNER=1` to use the older `Bot::Runner` only.

### Production/Single Process
To run only the legacy standalone gem runner from the repo root:

```bash
TZ=Asia/Kolkata bundle exec bin/run
```

## Stopping & Restarting

### Normal Stop
If the app was started in the foreground (e.g., using `./bin/dev`), simply press **`Ctrl+C`** in the terminal. This will trigger `foreman` to stop all associated services.

### Force Stop
If processes get stuck or you need to ensure a clean slate, use the following commands:

```bash
# Kill all related processes
pkill -9 -f "bin/bot" || true
pkill -9 -f "rails" || true
pkill -9 -f "puma" || true
pkill -9 -f "npm run dev" || true

# Remove stale PID file
rm -f backend/tmp/pids/server.pid
```

### Clearing Locks
If the bot was running through a `DeltaTradingJob` and crashed, it might have left a lock in Redis. Clear it with:

```bash
redis-cli del "delta_bot_lock:*"
```

## Tests

```bash
bundle exec rspec
```
