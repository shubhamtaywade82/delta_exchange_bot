---
name: delta-bot-rails-runtime
description: >-
  Canonical Delta Exchange bot runtime under backend/ (Trading::Runner, Solid Queue, paper vs live,
  Redis locks, EventBus). Use when editing trading execution, jobs, bootstrapping, fresh start,
  API, or when the user mentions bin/bot, DeltaTradingJob, legacy lib/bot, or canonical vs legacy paths.
---

# Delta Exchange bot — Rails canonical runtime

## Source of truth

- **Canonical code:** `backend/` Rails app. Prefer `backend/app/services/trading/` and `backend/app/services/bot/`.
- **Legacy:** repo root `lib/bot/` — do not extend unless the task explicitly targets it.
- **Entry:** `./bin/run` → `backend/bin/bot`. Full dev stack: `./bin/dev` from repo root.
- **Human/agent standards:** root `AGENTS.md`. Config merge order: `backend/docs/configuration_precedence.md`.
- **Architecture diagrams:** `backend/docs/architecture_diagrams.md`.

## Process invariants

- **At most one** long-lived trading loop per session. Do not run `bin/bot` and `DeltaTradingJob` concurrently for the same session (Redis `delta_bot_lock:<session_id>` helps; duplicate OS processes can still collide).
- **`Trading::EventBus`** is in-process global; `Trading::Runner#start` calls `EventBus.reset!` on exit — initializer subscriptions can be cleared when the runner stops; runner-specific handlers are registered in `register_event_handlers!`.
- **WebSocket:** `Trading::MarketData::WsClient` runs in a **thread** inside the runner process; writes `Rails.cache` `ltp:<symbol>` / `mark:<symbol>`, publishes `:tick_received`, routes fills/orders to `FillProcessor` / `OrderUpdater`.

## Execution modes

- **Paper:** `EXECUTION_MODE=paper` or Bot `dry_run` (see `Trading::PaperTrading`). Private WS streams may be skipped in paper; fills simulated via `Trading::ExecutionEngine`.
- **Live:** explicit Bot `live` mode + `EXECUTION_MODE=live`. Never enable live paths unless the user/task requires it.
- **Delta client:** `Trading::RunnerClient.build` for jobs and runner (same construction rules).

## Jobs (Solid Queue)

- Recurring schedules: `backend/config/recurring.yml` (requires `bin/jobs` / Procfile worker). This app uses **Solid Queue**, not Sidekiq.
- Examples: `Trading::ReconciliationJob`, `Trading::AnalysisDashboardRefreshJob`, `Trading::MarkPricesPnlJob`, `Delta::PaperProductsSyncJob`.

## Fresh start / Redis

- **Command:** `cd backend && CONFIRM=YES bin/rails trading:fresh_start` — see root `README.md` for full scope (Postgres tables + documented Redis `SCAN` + `Rails.cache.clear`).
- **SMC alert state:** pattern `delta:smc_alert:*` is included in fresh start cleanup.

## Verification

- **Tests:** `cd backend && bundle exec rspec` after behavior changes under `backend/`.
- **Primary suite:** `backend/spec/`; root `spec/` is legacy for `lib/bot/`.

## API boundary (workspace)

- This repo is **Delta Exchange India (crypto)** only. Do not introduce **DhanHQ** or Indian-market broker APIs here (see parent workspace `AGENTS.md` if present).
