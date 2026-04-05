# Repository-wide Audit TODO (2026-04-03)

This checklist captures repo-wide issues found during a broad static review of both the root bot code and the Rails backend/frontend stack.

## 0) Scope and assumptions
- Reviewed repository structure, key runtime entrypoints, service layer, test layout, and docs/config consistency.
- Focused on dead-code candidates, design drift, risk/safety gaps, and testing/code-review blind spots.
- This is a prioritized **fix backlog** (not all items are equally urgent).

---

## P0 — Architecture & production-safety risks

- [ ] **Choose a single source of truth for bot runtime code (root `lib/bot` vs `backend/app/services/bot`).**
  - 25 files share the same relative path in both trees (e.g. `runner.rb`, `execution/order_manager.rb`, all strategy indicators). The copies have diverged — `lib/bot/runner.rb` uses explicit `require_relative` while `backend/app/services/bot/runner.rb` relies on Rails autoloading with different timing constants.
  - `lib/bot/` is documented as legacy, but root `spec/bot/**` and `bin/test_indicators.rb` still load from it, so deletion requires migrating those consumers first.
  - Action: migrate root specs and scripts to use the canonical `backend/` implementation, then remove `lib/bot/` and enforce a single ownership boundary.

- [ ] **Clarify liquidation-safety naming and consolidate documentation.**
  - Only one `LiquidationGuard` class exists: `Trading::Risk::LiquidationGuard` (margin-usage classifier called from `Trading::Risk::Engine`). The separate mark-price proximity behavior lives in `Trading::NearLiquidationExit`. `Trading::LiquidationGuard` appears in planning docs but was never implemented as a class.
  - Action: update planning docs and diagrams to reference the actual class names, add cross-reference comments between the two services, and write contract specs that clarify the boundary between margin-safety (`LiquidationGuard`) and price-proximity (`NearLiquidationExit`) checks.

- [ ] **Eliminate broad rescue blocks around execution-critical flows.**
  - ~50 `rescue StandardError` sites exist across trading and bot services (39 in `trading/`, 11 in `bot/`). Highest concentration: `trading/runner.rb` (6), `market_data/ws_client.rb` (4), `bot/runner.rb` (5), `bot/execution/incident_store.rb` (5).
  - Action: replace with typed errors, structured logging payloads, and failure policies (halt session / disable symbol / retry with backoff). Start with the runner and WS client paths where swallowed exceptions can mask data-feed failures.

- [ ] **Remove money-critical float math from trading path.**
  - ~198 `.to_f` call-sites span 46 files under `backend/app/services/trading/`. Highest concentration: `dashboard/snapshot.rb` (37), `paper_wallet_publisher.rb` (13), `analysis/smc_price_action_snapshot.rb` (11), `risk/entry_gates_summary.rb` (10). Additionally `bot/execution/position_tracker.rb` has 15.
  - Action: migrate to `BigDecimal` end-to-end in risk/execution/accounting code, starting with the risk and execution namespaces. Isolate float conversion to UI-only serialization (dashboard, analysis snapshots).

---

## P1 — Dead code, drift, and ownership

- [ ] **Review and prune dead/partially-integrated service families in `backend/app/services/trading/**`.**
  - 69 of 153 service files have no matching `_spec.rb`. Notably untested runtime-wired services: `AdaptiveEngine` (called from `WsClient`), `Strategy::Selector` (called from `AdaptiveEngine`), `Microstructure::SignalEngine` and `LatencySignal` (called from `WsClient`), and `Learning::Explorer`/`Metrics`/`ParamProvider`. Handlers (`OrderHandler`, `PositionHandler`, `TrailingStopHandler`) are an exception — all have specs.
  - Action: produce a call-graph from active entrypoints (`Runner`, jobs, controllers), then deprecate or integrate modules explicitly. Prioritize spec coverage for `WsClient`, `AdaptiveEngine`, `Strategy::Selector`, and `Microstructure::SignalEngine`.

- [ ] **Resolve duplicated bot orchestration between legacy-style runner and newer Rails trading services.**
  - Current composition mixes `Bot::*` strategy runtime with `Trading::*` orchestration.
  - Action: define one orchestrator boundary and one event model; document migration plan and remove parallel pipelines.

- [ ] **Normalize event contracts and event bus usage.**
  - Event structs exist for multiple event types, but usage consistency and schema validation are not explicit.
  - Action: introduce typed event schema validation and contract tests for publishers/subscribers.

---

## P1 — Testing and review gaps

- [ ] **Close missing spec coverage for service objects in `backend/app/services/**`.**
  - 69 of 153 service files (~45%) lack a corresponding spec file. Coverage is weakest in: `bot/` (23 untested), `trading/analysis/` (10 untested SMC modules), `trading/execution/` (3 untested), `trading/events/` (5 untested event structs), and `trading/strategies/` (3 untested).
  - Action: prioritize high-risk runtime pieces first (WS client, execution router, risk engine components, kill-switch paths, funding/liquidation guards).

- [ ] **Add integration specs for end-to-end event lifecycle.**
  - Need deterministic tests for: market tick -> signal -> order placement -> fill processing -> position update -> risk reaction.
  - Action: use recorded fixtures + idempotency assertions + lock contention scenarios.

- [ ] **Add regression specs for failure modes and retries.**
  - Include WS disconnect/reconnect jitter behavior, queue overflow policy, API partial failures, and duplicate fill/order events.

---

## P2 — Data integrity & migrations

- [ ] **Harden reversible migration behavior for data backfills and constraint changes.**
  - Existing migrations with `up/down` backfills do not restore all prior null/default states on rollback.
  - Action: make rollback behavior explicit (or intentionally irreversible) and document operational rollback procedure.

- [ ] **Audit indexes against query patterns in risk and reconciliation loops.**
  - Action: validate active-position scans, dirty-position reconciliation, and order/fill lookup hot paths with `EXPLAIN` + composite index checklist.

---

## P2 — Security, reliability, and ops

- [ ] **Enforce webhook/event payload verification consistently (signature + schema + replay window).**
  - Action: add HMAC verification helpers and shared request spec examples for all inbound external payloads.

- [ ] **Standardize idempotency guarantees for all order/fill update entrypoints.**
  - Action: ensure unique external identifiers, advisory/row locking strategy, and duplicate-event test matrix are documented.

- [ ] **Define production runbooks for kill-switch / emergency unwind / degraded feed modes.**
  - Action: document operator actions, alert thresholds, and safe restart sequence.

---

## P3 — Docs & developer experience

- [ ] **Document canonical runtime architecture in one diagram + sequence flow.**
  - Action: update root README + backend README to remove ambiguity about which runner/services are authoritative.

- [ ] **Add a periodic code health gate in CI.**
  - Action: fail CI on new untested service files, dead-code thresholds, and unsafe rescue/float patterns in execution-risk namespaces.

- [ ] **Track this checklist as issue epics and link to implementation PRs.**
  - Action: split into epics (architecture, risk/math, test coverage, ops) with owners and target milestones.

---

## Quick wins (first pass)

- [ ] Freeze new feature work in duplicate bot paths (`lib/bot/`) until canonical runtime is chosen.
- [ ] Write contract specs for `Trading::Risk::LiquidationGuard` vs `Trading::NearLiquidationExit` boundary and kill-switch behavior.
- [ ] Replace highest-risk `to_f` call-sites with `BigDecimal` in `risk/`, `execution/`, and `order_builder.rb` (start with the ~30 sites in those namespaces).
- [ ] Add missing specs for `Trading::Market::WsClient`, `Trading::Execution::OrderRouter`, `Trading::Risk::Engine`, and `Trading::AdaptiveEngine`.
- [ ] Migrate root `spec/bot/**` tests to exercise `backend/app/services/bot/` directly instead of loading from `lib/bot/`.
- [ ] Publish one-page runtime ownership map (entrypoint -> orchestrator -> services).
