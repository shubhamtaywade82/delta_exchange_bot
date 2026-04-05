---
name: delta-bot-smc-analysis-telegram
description: >-
  SMC analysis dashboard digest (Solid Queue), SmcConfluence engine, tick-driven SMC Telegram event
  alerts, Ollama AiSmcSynthesizer, and Telegram notifications.telegram.events.analysis. Use when
  editing analysis jobs, SmcSnapshot/SmcConfluenceMtf, digest builder, Telegram analysis messages,
  or SMC alert Redis keys / ENV toggles.
---

# Delta bot — SMC analysis and Telegram

## Documentation

- **Event alerts (full spec):** `backend/docs/smc_event_alerts.md`
- **Config / Redis overview:** `backend/docs/configuration_precedence.md` (ephemeral keys + `ANALYSIS_SMC_ALERT_*`)

## Two Telegram paths (both use `events.analysis`)

1. **Scheduled digest (15m default)**  
   - Job: `Trading::AnalysisDashboardRefreshJob` in `backend/config/recurring.yml`.  
   - Builds per-symbol digest via `Trading::Analysis::DigestBuilder` (MTF candles, `SmcSnapshot`, `SmcConfluenceMtf`, optional `AiSmcSynthesizer`).  
   - Persists JSON: `Trading::Analysis::Store` → Redis key **`delta:analysis:dashboard`**.  
   - Telegram: `Trading::Analysis::DigestTelegramPush` → `notify_smc_analysis_digest` (chunked `ai_insight`).

2. **Tick-driven SMC event alerts**  
   - Only while **`Trading::Runner`** runs: `tick_received` → `Trading::Analysis::SmcAlertTickSubscriber` → `SmcAlertEvaluator`.  
   - Rising-edge flags vs Redis **`delta:smc_alert:prev:<symbol>`**; throttle **`delta:smc_alert:gate:<symbol>`**; cooldown **`delta:smc_alert:cooldown:<symbol>:<alert_id>`**.  
   - Optional AI once per burst: `DigestBuilder.ai_synthesis_from_loaded_candles` + `AiSmcSynthesizer`; Telegram `notify_smc_confluence_event` + chunked **`AI (SMC EVENT)`** on first alert in burst.  
   - **Bootstrap:** first eval stores state, **no** Telegram send.

## Confluence / Pine parity

- Engine: `backend/app/services/trading/analysis/smc_confluence/engine.rb` (+ `bar_result.rb`, `configuration.rb`).  
- MTF wrapper: `Trading::Analysis::SmcConfluenceMtf`.  
- Candles: `Trading::Analysis::HistoricalCandles` (REST, timeout + error policy).  
- Serialized last bar includes e.g. `long_signal`, `short_signal`, scores, CHOCH, liquidity sweeps, **`pdh_sweep`**, **`pdl_sweep`**.

## Environment toggles (event path)

- `ANALYSIS_SMC_ALERT_ENABLED` — `false` disables event alerts.  
- `ANALYSIS_SMC_ALERT_INCLUDE_AI` — `false` skips Ollama on bursts.  
- `ANALYSIS_SMC_ALERT_MIN_INTERVAL_S` (default `15`) — gate TTL.  
- `ANALYSIS_SMC_ALERT_COOLDOWN_S` (default `300`) — per-alert cooldown.  
- Ollama connectivity/timeouts: same as digest (`Ai::OllamaClient`, `OLLAMA_*`).

## Telegram config

- Loaded via `Bot::Config.load`; requires `notifications.telegram.enabled` and **`notifications.telegram.events.analysis`** for analysis-style pushes.  
- Bridge from trading code: `Trading::TelegramNotifications` → `Bot::Notifications::TelegramNotifier`.

## Tests

- Touching digest/alert behavior: extend `backend/spec/services/trading/analysis/*`, `telegram_notifier_spec`, `digest_builder_spec`, `smc_alert_evaluator_spec` as appropriate.
