# Delta Exchange Bot — consolidated TODO

**Sources:** [docs/repo_audit_backlog.md](docs/repo_audit_backlog.md), [docs/repo_audit_todo_2026-04-03.md](docs/repo_audit_todo_2026-04-03.md)  
**Last merged:** 2026-04-03

---

## Plan

### Objective

Turn the 2026-04-03 repo audits into one prioritized, checkable backlog for the canonical **Rails runtime under `backend/`**, while tracking cross-cutting items (legacy `lib/bot/`, frontend, CI, docs).

### Sequencing (suggested)

1. **Safety first (P0):** session/portfolio scoping for emergency shutdown and risk checks; order fill / side normalization; align with regression tests before refactors that touch money paths.
2. **Architecture clarity (P1):** duplicate `LiquidationGuard` naming and contracts; error policy for hot paths; explicit `Position.active` scopes; `ollama-client` provisioning.
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

- [ ] **Emergency shutdown:** scope `close_open_positions!` to the target session/portfolio (today `cancel_open_orders!` is session-scoped but positions use global `Position.active`).  
  - Files: `backend/app/services/trading/emergency_shutdown.rb`  
  - Tests: multi-session — only target session flattened; orders and positions scoped consistently (`emergency_shutdown_spec`).

- [ ] **Risk manager scope:** make `check_max_concurrent_positions!`, `check_margin_utilization!`, and related checks consistent with `check_pyramiding!` (global `Position.active` vs session portfolio).  
  - Files: `backend/app/services/trading/risk_manager.rb`  
  - Tests: unrelated portfolios do not affect scoped checks; daily loss cap semantics explicit (`risk_manager_spec` or equivalent).

- [ ] **Order fill / position side:** stop assuming raw `buy` = open and `sell` = close; normalize position intent at one boundary.  
  - Files: `backend/app/services/trading/handlers/order_handler.rb`  
  - Tests: long/short open and close; trade creation uses normalized side.

- [ ] **Single canonical bot runtime (safety + drift):** choose root `lib/bot/**` vs `backend/app/services/bot/**` as the only implementation surface; deprecate or wrap the other.  
  - Supported entrypoint is the Rails backend (`backend/bin/bot`); root `lib/bot/runner.rb` uses different timings/wiring and is a drift/misuse risk.  
  - Aligns backlog items 8–9 with todo “single source of truth.”

- [ ] **Liquidation guards — contract and naming:** unify `Trading::LiquidationGuard` vs `Trading::Risk::LiquidationGuard` (rename and/or single interface + call-site wiring).  
  - Files: `backend/app/services/trading/liquidation_guard.rb`, `backend/app/services/trading/risk/liquidation_guard.rb`  
  - Backlog suggested rename examples: `NearLiquidationExit`, `LiquidationPriceGuard`, or similarly explicit names.  
  - Add/finish tests for runtime liquidation distance threshold, missing liquidation price, long/short close side (the `trading/risk/` guard already has some coverage; mirror intent for the runtime path).

- [ ] **Error policy on hot paths:** replace or narrow broad rescue-and-log in execution-critical flows; define reconcile vs fail-loud vs safe-ignore.  
  - Files called out: `order_handler.rb`, `emergency_shutdown.rb`, other event-driven trading services.

- [ ] **Money-critical numeric path (from todo audit):** reduce `to_f`/float usage in price, margin, PnL, and risk; prefer `BigDecimal` in risk/execution/accounting, float only at UI serialization boundaries.

---

## P1 — Architecture, operations, and integration

- [ ] **`Position.active` intent:** introduce explicit scopes/names (`active_positions_for_portfolio`, `all_active_positions`, `session_positions`, etc.) and migrate call-sites.  
  - Includes: `liquidation_guard.rb`, `funding_monitor.rb`, `risk/entry_gates_summary.rb`, `paper_wallet_publisher.rb`, `mark_prices_pnl_job.rb`, `position_reconciliation.rb`, others found by search.

- [ ] **`ollama-client` path dependency:** document and automate provisioning (publish, vendor, submodule, or CI checkout) so bundle matches `Gemfile` path — backlog notes CI/docs treat it unlike the `delta_exchange` path gem, so expectations should be explicit for both.  
  - Files: `backend/Gemfile`, `backend/Gemfile.lock`, `.github/workflows/ci.yml`, `.github/workflows/deploy.yml`, `.github/README.md`.

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

- [ ] **`Trading::Handlers::OrderHandler`:** unit/integration tests for fills, events, trade on close, error/reconciliation behavior.  
  - Files: `backend/app/services/trading/handlers/order_handler.rb`

- [ ] **Integration specs (todo):** market tick → signal → order → fill → position → risk reaction (fixtures, idempotency, lock contention).

- [ ] **Failure-mode regression (todo):** WS disconnect/reconnect, queue overflow, API partial failures, duplicate fill/order events.

- [ ] **`backend/bin/ci`:** add `bundle exec rspec` or rename/document as lint/security-only (`backend/config/ci.rb`).

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

- [ ] **`.github/README.md`:** clarify required vs optional path gems (`DELTA_EXCHANGE_REPOSITORY`, `ollama-client` availability vs CI reality).

- [ ] **Canonical architecture:** one diagram + sequence (root README + backend README) — todo.

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
5. **Naming:** Could this class be confused with another (e.g. two `LiquidationGuard`s)?

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

**Third wave:** reproducible `ollama-client` provisioning; frontend tests in CI; clarify `backend/bin/ci`; mark/refresh stale planning docs; reduce duplicated bot config sources.
