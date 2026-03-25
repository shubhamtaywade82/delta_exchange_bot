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
