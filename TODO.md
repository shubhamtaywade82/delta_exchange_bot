# Delta Exchange Bot — consolidated TODO

**Sources:** [docs/repo_audit_backlog.md](docs/repo_audit_backlog.md), [docs/repo_audit_todo_2026-04-03.md](docs/repo_audit_todo_2026-04-03.md)  
**Last merged:** 2026-04-05

---

## Incremental execution (no unnecessary regressions)

Work through items **in priority order**, one PR-sized slice at a time.

1. **Prefer tests-first** when changing behavior: add or extend specs that describe the *intended* contract (especially session/portfolio boundaries) before or alongside the fix.
2. **Preserve observable behavior** when the audit calls out *bugs* only for multi-tenant/multi-session cases: single-session deployments should keep seeing the same outcomes (e.g. only that session’s positions affected).
3. **Avoid drive-by refactors**: touch only the files and call-sites required for the current item.
4. **Document intentional behavior changes** in the commit/PR when a fix corrects unsafe global behavior (call it out so operators know what changed).
5. **Run** `cd backend && bundle exec rspec` after backend changes.

**Done in repo (track here):**

- [x] **P0 — Emergency shutdown:** `close_open_positions!` scoped to the target session’s `portfolio_id` (was `Position.active` globally). Specs: multi-session positions and orders isolation (`emergency_shutdown_spec`).
- [x] **P0 — Risk manager:** max concurrent positions, margin utilization, pyramiding existence check, and daily loss cap all use the **session’s portfolio** (`active_positions_for_session_portfolio` + `Trade` scoped by `portfolio_id`). **Semantic change:** rows with `trades.portfolio_id` nil no longer count toward any session’s daily loss cap (fills from `OrderHandler` / `CreditAssigner` set `portfolio_id`). Specs: `risk_manager_spec` (+ cross-portfolio isolation examples).
- [x] **P0 — Order fill / position intent:** `PositionsRepository` now infers **open vs close** from order side + existing net side (sell closes long, buy closes short; opposite opens). Fills are **portfolio-scoped** (`open_for`, `close!`, `upsert_from_order`). `OrderHandler` snapshots the open position **before** close so `Trade` rows are created correctly. **Note:** the live WS path still runs through `FillProcessor` / `PositionRecalculator`; `OrderHandler` remains the contract for `:order_filled` if published. Specs: `spec/repositories/positions_repository_spec.rb`, `spec/services/trading/handlers/order_handler_spec.rb`.
- [x] **P1 — Near-liquidation naming + CI script:** runner mark-price emergency exit renamed to `Trading::NearLiquidationExit` (file `near_liquidation_exit.rb`); `Trading::Risk::LiquidationGuard` unchanged (margin ratio). Specs: `near_liquidation_exit_spec.rb`. `backend/bin/ci` now runs `bundle exec rspec` after lint/security (`config/ci.rb` header documents scope).
- [x] **P1 — `Position.active_for_portfolio`:** named scope on `Position`; portfolio-scoped queries updated in `PositionsRepository`, `EmergencyShutdown`, `RiskManager`, `PaperWalletPublisher`, `MarginAffordability`. `NearLiquidationExit` keeps a global scan (commented) and uses `find_each` for batching. Spec: `position_spec` (`active_for_portfolio`). Remaining `Position.active` uses are intentional cross-session/portfolio scans or dashboard-wide views — migrate in a later pass if needed.
- [x] **P0 — Hot-path error policy (baseline):** `HotPathErrorPolicy.log_swallowed_error` — `log_level:`, `report_handled:` (default `true`; `false` when error is re-raised). Wired in `EmergencyShutdown`, `OrderHandler`, `FillProcessor`, `PositionHandler`, `EventBus`, `FundingMonitor`, `MarketData::WsClient`, `ExecutionEngine`, `Bootstrap::Sync*`, **`MarketData::OhlcvFetcher`** (`fetch`, warn + `[]`), **`Analysis::HistoricalCandles`** (`fetch`, warn + `[]`; `Timeout::Error` includes `reason=timeout`), **`Delta::ProductCatalogSync`** (`sync_one!`), **`Analysis::AiSmcSynthesizer`** (`call`; `reason` `ruby_timeout` / `ollama_timeout` / `error`), **`Analysis::Store`** (`read`; invalid JSON / Redis errors), **`PaperWalletPublisher`**, **`PositionReconciliation`**, **`TelegramNotifications`**, **`Runner`** (`execute_signal` re-raises without duplicate report — `ExecutionEngine` + outer `run_strategy` cover execution failures), **`SessionResumer`**, **`PaperTrading`** (`enabled?` when `Bot::Config.load` fails), **`FreshStart`** (Redis DEL / SCAN / `Rails.cache.clear` soft-fail paths), **`RuntimeConfig`** (`fetch_boolean` only), **`Strategy::AiEdgeModel`** (`call`), **`Learning::AiRefinementTrigger`** (`call`). Specs: `ohlcv_fetcher_spec`, `historical_candles_spec`, `product_catalog_sync_spec`, `ai_smc_synthesizer_spec`, `analysis/store_spec`, `paper_wallet_publisher_spec`, `position_reconciliation_spec`, `telegram_notifications_spec`, `runner_signal_persistence_spec`, `session_resumer_spec`, `paper_trading_spec`, `fresh_start_spec`, `runtime_config_spec`, `strategy/ai_edge_model_spec`, `learning/ai_refinement_trigger_spec`. **Follow-up:** remaining swallowed `rescue` in dashboard / risk helpers; per-flow reconcile vs fail-loud.
- [x] **P0 — BigDecimal (risk + execution prices slice):** `RiskManager` denominator / margin / daily-loss (prior). **`ExecutionEngine`** `resolve_intended_fill_price` and `synthetic_fill_price` use `decimal_price` (`.to_d`, blank → `0`, invalid → `0`) instead of `to_f` for LTP/order price. **Follow-up:** remaining execution / PnL `to_f`; UI serialization boundaries.
- [x] **P3 — SMC Telegram event alerts + docs:** `Trading::Analysis::SmcAlertEvaluator` / `SmcAlertTickSubscriber` on `tick_received` (runner); rising-edge confluence alerts, Redis gate/cooldown/state, optional Ollama via `DigestBuilder.ai_synthesis_from_loaded_candles`; `pdh_sweep`/`pdl_sweep` on `BarResult`; `FreshStart` clears `delta:smc_alert:*`. Documented in [`backend/docs/smc_event_alerts.md`](backend/docs/smc_event_alerts.md); root `README` / `backend/README` / `configuration_precedence` / `architecture_diagrams` updated.

---

## Plan

### Objective

Turn the 2026-04-03 repo audits into one prioritized, checkable backlog for the canonical **Rails runtime under `backend/`**, while tracking cross-cutting items (legacy `lib/bot/`, frontend, CI, docs).

### Sequencing (suggested)

1. **Safety first (P0):** session/portfolio scoping for emergency shutdown and risk checks; order fill / side normalization; align with regression tests before refactors that touch money paths.
2. **Architecture clarity (P1):** ~~duplicate `LiquidationGuard` naming~~ (addressed: `NearLiquidationExit` vs `Risk::LiquidationGuard`); ~~baseline hot-path error policy~~ (`HotPathErrorPolicy`); explicit `Position.active` scopes; `ollama-client` provisioning.
3. **Debt reduction (P2):** legacy vs backend bot duplication, WebSocket patches, specs, `backend/bin/ci`, frontend tests in CI.
4. **DX and docs (P3):** README/planning docs, dual `bot.yml`, `.github/README.md` accuracy.

### Risks

- **Scope policy:** Global vs per-portfolio risk and shutdown semantics must be decided explicitly; wrong choice leaks positions across sessions or blocks legitimate trading.
- **Refactor drift:** Fixing one of two parallel bot stacks or duplicate guards without deleting or hard-deprecating the other invites partial fixes.
- **Silent failure:** Broad rescues and float math in money paths can mask bugs until production; changes need tests and possibly staged rollout.

### Unknowns / decisions needed

- Authoritative **risk scope** (global vs portfolio vs session) for max positions, margin, and daily loss.
- **Fate of root `lib/bot/`** and root `spec/bot/**` (delete, archive, or thin compatibility layer).
- Whether **BigDecimal migration** is in scope for the next milestone or a dedicated epic (todo audit calls it out; backlog focuses on scoping and side normalization first).

### Priority legend

| Tag | Meaning |
|-----|---------|
| **P0** | Safety or correctness |
| **P1** | Architecture or operational risk |
| **P2** | Maintainability, coverage, data/ops hardening |
| **P3** | Documentation, tooling, developer experience |

---

## P0 — Safety and correctness

- [x] **Emergency shutdown:** scope position flattening to the target session’s portfolio (`Position.active.where(portfolio_id: …)`); orders were already session-scoped.  
  - Files: `backend/app/services/trading/emergency_shutdown.rb`  
  - Tests: `backend/spec/services/trading/emergency_shutdown_spec.rb` (multi-session positions + orders).

- [x] **Risk manager scope:** max concurrent, margin utilization, pyramiding, and daily loss cap aligned on the session’s `portfolio_id`.  
  - Files: `backend/app/services/trading/risk_manager.rb`  
  - Tests: `backend/spec/services/trading/risk_manager_spec.rb`

- [x] **Order fill / position side:** open vs close derived in `PositionsRepository` from existing position net side + order side; `OrderHandler` uses `snapshot_for_closing_trade` + `apply_fill_from_order!`.  
  - Files: `backend/app/repositories/positions_repository.rb`, `backend/app/services/trading/handlers/order_handler.rb`  
  - Tests: `positions_repository_spec`, `order_handler_spec`.

- [ ] **Single canonical bot runtime (safety + drift):** choose root `lib/bot/**` vs `backend/app/services/bot/**` as the only implementation surface; deprecate or wrap the other.  
  - Supported entrypoint is the Rails backend (`backend/bin/bot`); root `lib/bot/runner.rb` uses different timings/wiring and is a drift/misuse risk.  
  - Aligns backlog items 8–9 with todo “single source of truth.”

- [x] **Liquidation guards — contract and naming:** runner LTP-distance exit is `Trading::NearLiquidationExit`; margin-ratio classification stays `Trading::Risk::LiquidationGuard`.  
  - Files: `backend/app/services/trading/near_liquidation_exit.rb`, `backend/app/services/trading/risk/liquidation_guard.rb`  
  - Tests: `backend/spec/services/trading/near_liquidation_exit_spec.rb`, `backend/spec/services/trading/risk/liquidation_guard_spec.rb`

- [x] **Error policy on hot paths (baseline):** `Trading::HotPathErrorPolicy` on `emergency_shutdown.rb`, `order_handler.rb`, `fill_processor.rb` (paper wallet publish), `position_handler.rb` — still **swallowed**.  
  - **Follow-up:** dashboard / risk helper rescues; per-flow reconcile vs fail-loud (see “Hot-path error policy” bullet above).

- [ ] **Money-critical numeric path (remaining):** extend `BigDecimal` beyond `RiskManager` denominator / margin / daily-loss checks (execution prices, PnL paths, etc.); float only at UI serialization boundaries.

---

## P1 — Architecture, operations, and integration

- [ ] **`Position.active` intent (remaining):** optional follow-up — name or document **global** scans (`funding_monitor.rb`, `risk/entry_gates_summary.rb`, `mark_prices_pnl_job.rb`, `position_reconciliation.rb`, `ws_client.rb`, `dashboard/snapshot.rb`, `bootstrap/sync_positions.rb`, `risk/portfolio_snapshot.rb`, API `positions_controller`, `bot/execution/position_tracker.rb`). Portfolio-scoped paths now use `Position.active_for_portfolio` where applicable.

- [ ] **Orchestration boundary:** one orchestrator and one event model between `Bot::*` strategy runtime and `Trading::*` (todo); document migration and remove parallel pipelines where safe.

- [ ] **Event contracts:** typed event schemas, validation, and contract tests for publishers/subscribers (todo).

- [ ] **Trading service inventory:** call-graph from `Runner`, jobs, controllers; deprecate or integrate low-wiring modules under `backend/app/services/trading/**` (todo).

---

## P2 — Maintainability, tests, data, security

### Duplicate / legacy stack

- [ ] **Duplicate WebSocket patches:** one canonical patch — `lib/bot/feed/delta_ws_patch.rb`, `backend/config/initializers/delta_exchange_ws_connection_patch.rb`, `backend/lib/patches/delta_exchange_ws_connection_patch.rb`.

- [ ] **Legacy indicators / smoke:** `lib/bot/indicators/provider.rb`, `bin/test_indicators.rb` — delete, move to backend with tests, or rename as legacy-only.

- [ ] **Root vs backend specs:** single source of truth for bot behavior tests (`spec/bot/**` vs `backend/spec/services/bot/**`).

- [ ] **Deletion candidates (explicit decision):** `lib/bot/runner.rb`, overlapping `lib/bot/**`, root `spec/bot/**`, stale planning docs under `docs/superpowers/**` when superseded.

### Specs and CI

- [ ] **Service spec gap closure (todo audit):** many `backend/app/services/**` objects lack matching `backend/spec/services/**` coverage — prioritize high-risk runtime pieces first: WebSocket ingestion, routing, risk executor, kill-switch paths, funding and liquidation guards.

- [ ] **`Trading::Handlers::OrderHandler`:** extend coverage for error/reconciliation paths and any future `:order_filled` wiring.  
  - Files: `backend/app/services/trading/handlers/order_handler.rb` (baseline: `order_handler_spec` — close long/short, portfolio isolation, not-filled no-op)

- [ ] **Integration specs (todo):** market tick → signal → order → fill → position → risk reaction (fixtures, idempotency, lock contention).

- [ ] **Failure-mode regression (todo):** WS disconnect/reconnect, queue overflow, API partial failures, duplicate fill/order events.

- [x] **`backend/bin/ci`:** runs `bundle exec rspec` after RuboCop and security steps; header comment in `backend/config/ci.rb` describes full scope.

- [ ] **Frontend CI:** add a minimal automated test layer beyond lint/audit/build (`frontend/package.json`, `.github/workflows/ci.yml`).

### Data, indexes, idempotency (todo audit)

- [ ] **Reversible migrations:** backfills/constraints — explicit rollback or documented irreversibility.

- [ ] **Index audit:** active-position scans, reconciliation, order/fill hot paths (`EXPLAIN`, composite indexes).

- [ ] **Webhook/payload verification:** HMAC, schema, replay window; shared request spec patterns.

- [ ] **Idempotency:** document and test order/fill entrypoints (external IDs, locking, duplicate events).

### Ops

- [ ] **Runbooks:** kill-switch, emergency unwind, degraded feed — operator steps, alerts, safe restart (todo).

---

## P3 — Documentation and developer experience

- [ ] **Stale planning docs:** mark historical or refresh paths/stack. Backlog called out explicitly:  
  - `docs/superpowers/plans/2026-03-26-delta-exchange-bot.md`  
  - `docs/superpowers/plans/2026-03-28-minimal-winning-stack.md`  
  - `backend/docs/superpowers/plans/2026-03-26-rails-bot-integration.md`  
  - (and any other historical plans that mention old Ruby/frontend versions or wrong paths.)

- [ ] **Dual `bot.yml`:** one source of truth, generation, or drift check (`README.md`, `config/bot.yml`, `backend/config/bot.yml`).

- [ ] **Canonical architecture:** one diagram + sequence (root README + backend README) — partial: see [`backend/docs/architecture_diagrams.md`](backend/docs/architecture_diagrams.md) and [`backend/docs/smc_event_alerts.md`](backend/docs/smc_event_alerts.md); keep README cross-links in sync when runtime changes.

- [ ] **CI code-health gate (todo):** optional fail on new untested services, thresholds, unsafe patterns in execution-risk namespaces.

- [ ] **Track epics (todo):** split into issues (architecture, risk/math, tests, ops) with owners and milestones.

---

## Quick wins (from todo audit — first week)

- [ ] Freeze new features in duplicate bot paths until canonical runtime is chosen.
- [ ] Contract tests for liquidation + kill-switch; remove semantic duplication where possible.
- [ ] Replace top money-critical `to_f` call-sites in risk/execution with `BigDecimal` (incremental).
- [ ] Add specs for WS client, execution router, risk executor (prioritize highest-risk gaps).
- [ ] One-page runtime ownership map: entrypoint → orchestrator → services.

---

## Code review prompts (from backlog)

Use in PRs touching trading code:

1. **Scope:** Is this query intentionally global, or session/portfolio-scoped? Does the name say so?
2. **Boundaries:** Are exchange sides normalized once, or leaking raw strings into domain logic?
3. **Duplicates:** Does the same behavior exist under root `lib/bot/` or root `spec/`? Should one path be removed instead of updated?
4. **Errors:** Is broad rescue appropriate? Re-raise, reconcile, or fail session?
5. **Naming:** Could this class be confused with another (e.g. `NearLiquidationExit` vs `Risk::LiquidationGuard`)?

---

## Definition of done (cleanup PRs)

- Names reveal intent; session/portfolio scoping is explicit.
- Legacy paths removed or clearly deprecated.
- Tests target the real backend runtime, not a parallel copy.
- Docs describe one supported workflow for running and configuring the bot.

---

## Backlog “suggested cleanup sequence” (reference)

The audit backlog grouped work into three waves; items above subsume these — kept here for ordering only.

**First wave:** emergency shutdown + risk manager scoping; regression tests; rename one `LiquidationGuard`; direct tests for runtime liquidation exit.

**Second wave:** decide fate of root `lib/bot/` and root `spec/`; remove/deprecate `bin/test_indicators.rb`; consolidate WebSocket patches; normalize side handling across repos/services.

**Third wave:** reproducible `ollama-client` provisioning; frontend tests in CI; ~~clarify `backend/bin/ci`~~; mark/refresh stale planning docs; reduce duplicated bot config sources.
