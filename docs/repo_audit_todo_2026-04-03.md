# Repository-wide Audit TODO (2026-04-03)

This checklist captures repo-wide issues found during a broad static review of both the root bot code and the Rails backend/frontend stack.

## 0) Scope and assumptions
- Reviewed repository structure, key runtime entrypoints, service layer, test layout, and docs/config consistency.
- Focused on dead-code candidates, design drift, risk/safety gaps, and testing/code-review blind spots.
- This is a prioritized **fix backlog** (not all items are equally urgent).

---

## P0 — Architecture & production-safety risks

- [ ] **Choose a single source of truth for bot runtime code (root `lib/bot` vs `backend/app/services/bot`).**
  - There are duplicate implementations across both trees with a mix of identical and diverging files, increasing drift risk and review overhead.
  - Action: keep only one canonical implementation, convert the other to wrapper/adapters, and enforce ownership boundaries.

- [ ] **Unify liquidation guard behavior and naming.**
  - Two different liquidation guard concepts exist: `Trading::LiquidationGuard` and `Trading::Risk::LiquidationGuard` with different semantics.
  - Action: keep one risk contract and wire all call-sites through that single interface.

- [ ] **Eliminate broad rescue blocks around execution-critical flows.**
  - Several core runtime paths swallow broad exceptions and continue.
  - Action: replace with typed errors, structured logging payloads, and failure policies (halt session / disable symbol / retry with backoff).

- [ ] **Remove money-critical float math from trading path.**
  - Price, margin, PnL, and risk calculations still depend on `to_f`/float conversions in multiple services.
  - Action: migrate to `BigDecimal` end-to-end in risk/execution/accounting code and isolate float conversion to UI-only serialization.

---

## P1 — Dead code, drift, and ownership

- [ ] **Review and prune dead/partially-integrated service families in `backend/app/services/trading/**`.**
  - There are many modules with little/no test coverage and unclear runtime wiring (adaptive engine, microstructure, learning helpers, handlers, strategy selector, etc.).
  - Action: produce a call-graph from active entrypoints (`Runner`, jobs, controllers), then deprecate or integrate modules explicitly.

- [ ] **Resolve duplicated bot orchestration between legacy-style runner and newer Rails trading services.**
  - Current composition mixes `Bot::*` strategy runtime with `Trading::*` orchestration.
  - Action: define one orchestrator boundary and one event model; document migration plan and remove parallel pipelines.

- [ ] **Normalize event contracts and event bus usage.**
  - Event structs exist for multiple event types, but usage consistency and schema validation are not explicit.
  - Action: introduce typed event schema validation and contract tests for publishers/subscribers.

---

## P1 — Testing and review gaps

- [ ] **Close missing spec coverage for service objects in `backend/app/services/**`.**
  - Many production services do not have matching specs under `backend/spec/services/**`.
  - Action: prioritize high-risk runtime pieces first (WS ingestion, routing, risk executor, kill-switch paths, funding/liquidation guards).

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

## Quick wins (first week)

- [ ] Freeze new feature work in duplicate bot paths until canonical runtime is chosen.
- [ ] Write contract tests for liquidation + kill-switch behavior and remove semantic duplication.
- [ ] Replace top 10 money-critical `to_f` call-sites with `BigDecimal` in risk/execution paths.
- [ ] Add missing specs for WS client, execution router, and risk executor.
- [ ] Publish one-page runtime ownership map (entrypoint -> orchestrator -> services).
