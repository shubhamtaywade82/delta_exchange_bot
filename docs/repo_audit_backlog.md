# Repository Audit Backlog

Point-in-time whole-repo audit captured on 2026-04-03.

**After this date:** several **P0** items called out here were fixed (emergency shutdown and risk scoping, order fill semantics, `NearLiquidationExit` naming, hot-path error policy baseline, etc.). Track what landed in **[`TODO.md`](../TODO.md)** (Done section) before treating a finding as still open.

Purpose:

- keep a durable backlog of cross-repo issues
- separate high-risk bugs from cleanup debt
- give future fix work concrete file targets

This repo has one dominant theme: the canonical Rails runtime under `backend/` is carrying real trading logic, but the repo still contains an overlapping legacy bot stack under root `lib/bot/` and root `spec/`. That duplication increases drift, review confusion, and dead-code risk.

## Priority legend

- **P0**: safety or correctness risk
- **P1**: high-value architecture or operational risk
- **P2**: maintainability or coverage gap
- **P3**: documentation or tooling cleanup

## P0 - Safety and correctness

### 1) Emergency shutdown closes every active position globally

- **Files:** `backend/app/services/trading/emergency_shutdown.rb`
- **Problem:** `cancel_open_orders!` scopes by `trading_session_id`, but `close_open_positions!` iterates `Position.active` with no session or portfolio filter.
- **Risk:** one emergency stop can flatten positions owned by other sessions or portfolios.
- **Fix direction:** scope position shutdown by session-owned portfolio, or make the shutdown API explicit about whether it is session-local or global.
- **Follow-up tests:**
  - multi-session shutdown only closes positions for the target session
  - orders and positions are scoped consistently

### 2) Risk checks mix per-session logic with global position aggregates

- **Files:** `backend/app/services/trading/risk_manager.rb`
- **Problem:** `check_max_concurrent_positions!` and `check_margin_utilization!` use global `Position.active`, while `check_pyramiding!` uses the current session portfolio.
- **Risk:** one portfolio can block entries or distort margin checks for another.
- **Fix direction:** decide whether risk enforcement is global or per-portfolio, then make all checks consistent and intention-revealing.
- **Follow-up tests:**
  - positions in another portfolio do not affect this session when policy is portfolio-scoped
  - daily loss cap semantics are explicit and tested against the chosen scope

### 3) Order fill handling assumes `buy` opens and `sell` closes

- **Files:** `backend/app/services/trading/handlers/order_handler.rb`
- **Problem:** `update_position` treats any `buy` as open and any `sell` as close.
- **Risk:** short-opening or mixed-side flows can be recorded incorrectly, especially if side normalization ever varies between exchange payloads and persisted positions.
- **Fix direction:** normalize position intent once at the repository or domain boundary and stop branching on raw exchange side strings in downstream services.
- **Follow-up tests:**
  - fill handling for long open, long close, short open, short close
  - trade creation uses the normalized position side, not transport-specific values

## P1 - Architecture and operational risks

### 4) Liquidation-safety naming can mislead reviewers

- **Files:**
  - `backend/app/services/trading/risk/liquidation_guard.rb` — classifies margin-ratio safety (:safe / :danger / :liquidation)
  - `backend/app/services/trading/near_liquidation_exit.rb` — force-exits positions near mark-price liquidation threshold
  - `backend/app/services/trading/liquidation_engine.rb` — delegates to `Risk::Engine` + `Risk::Executor`
- **Problem:** three separate liquidation-related services with overlapping names. Planning docs still reference a nonexistent `Trading::LiquidationGuard` class.
- **Risk:** developers and reviewers can confuse the margin-ratio classifier with the price-proximity exit and think liquidation behavior is covered when it is not.
- **Fix direction:** add cross-reference comments between all three services, update planning docs to use correct class names, and write contract specs that clarify the boundary between each.

### 5) Broad rescue-and-log behavior can hide state drift

- **Files:**
  - `backend/app/services/trading/handlers/order_handler.rb`
  - `backend/app/services/trading/emergency_shutdown.rb`
  - other event-driven trading services with broad rescue blocks
- **Problem:** unexpected errors are logged and swallowed in hot paths.
- **Risk:** the process stays alive while orders, positions, or trades drift out of sync.
- **Fix direction:** define a clear error policy for event handlers:
  - what can be safely logged and ignored
  - what must trigger reconciliation
  - what must fail loudly

### 6) `Position.active` is used globally in many services

- **Files:**
  - `backend/app/services/trading/near_liquidation_exit.rb`
  - `backend/app/services/trading/funding_monitor.rb`
  - `backend/app/services/trading/risk/entry_gates_summary.rb`
  - `backend/app/services/trading/paper_wallet_publisher.rb`
  - `backend/app/jobs/trading/mark_prices_pnl_job.rb`
  - `backend/app/services/trading/position_reconciliation.rb`
  - other trading services discovered via search
- **Problem:** many services use global active positions without clearly naming whether that is intentional.
- **Risk:** tenant bleed, review ambiguity, and future regressions whenever multi-session behavior changes.
- **Fix direction:** introduce explicit scopes and names that reveal intent, for example:
  - `active_positions_for_portfolio`
  - `all_active_positions`
  - `session_positions`

### 7) Local path dependency on `ollama-client` is under-documented and brittle

- **Files:**
  - `backend/Gemfile`
  - `backend/Gemfile.lock`
  - `.github/workflows/ci.yml`
  - `.github/workflows/deploy.yml`
  - `.github/README.md`
- **Problem:** `ollama-client` is loaded from `../../../ai-workspace/ollama-client`, but CI/docs do not provision it the same way as `delta_exchange`.
- **Risk:** fresh clones, CI, or new environments can fail at bundle time in ways that are not obvious.
- **Fix direction:** publish, vendor, submodule, or explicitly check out the dependency in automation.

## P2 - Duplicate code, dead code, and maintainability debt

### 8) Repo carries two overlapping bot runtimes with the same names

- **Files:**
  - root `lib/bot/**`
  - `backend/app/services/bot/**`
  - `backend/bin/bot`
- **Problem:** there are two `Bot::*` trees with overlapping class names and responsibilities.
- **Examples:**
  - `lib/bot/runner.rb`
  - `backend/app/services/bot/runner.rb`
- **Risk:** fixes land in one implementation but not the other, and class names are similar enough to mislead contributors.
- **Fix direction:** either retire the root stack or narrow it to a clearly documented compatibility layer.

### 9) Root `lib/bot/runner.rb` looks stale relative to the supported runtime

- **Files:** `lib/bot/runner.rb`, `backend/bin/bot`, `README.md`
- **Problem:** the root runner uses materially different timings and wiring, but the supported runtime is the Rails backend.
- **Risk:** misleading fallback code remains available for ad-hoc use and may quietly drift.
- **Fix direction:** deprecate, archive, or delete the root runner once its remaining use cases are identified.

### 10) Duplicate WebSocket patch implementations

- **Files:**
  - `lib/bot/feed/delta_ws_patch.rb`
  - `backend/config/initializers/delta_exchange_ws_connection_patch.rb`
  - `backend/lib/patches/delta_exchange_ws_connection_patch.rb`
- **Problem:** the same integration concern exists in both the legacy root stack and the backend stack.
- **Risk:** protocol fixes or auth fixes can diverge.
- **Fix direction:** keep one canonical patch path or clearly isolate the legacy copy until removal.

### 11) `Bot::Indicators::Provider` appears isolated to the legacy path

- **Files:**
  - `lib/bot/indicators/provider.rb`
  - `bin/test_indicators.rb`
- **Problem:** the provider is used by a root smoke script, not the canonical backend strategy stack.
- **Risk:** maintenance cost without production value.
- **Fix direction:** delete it if obsolete, or move the behavior into the backend runtime and give it production-facing tests.

### 12) Root and backend specs duplicate behavior

- **Files:**
  - root `spec/bot/**`
  - `backend/spec/services/bot/**`
  - `README.md`
- **Problem:** similar strategy behavior is tested twice in different harnesses.
- **Risk:** drift, duplicate maintenance, and false confidence when only one suite is exercised regularly.
- **Fix direction:** choose one source of truth for bot behavior tests and archive or remove the duplicate suite.

### 13) `bin/test_indicators.rb` is a misleading manual smoke script

- **Files:** `bin/test_indicators.rb`
- **Problem:** the script explicitly does not run the backend implementation and instead treats a legacy provider smoke test as enough.
- **Risk:** contributors may think production RSI behavior is validated when it is not.
- **Fix direction:** remove it, rename it to say "legacy smoke", or rewrite it to boot Rails and exercise the real path.

### 14) `backend/bin/ci` does not run the test suite

- **Files:** `backend/config/ci.rb`
- **Problem:** local CI runs setup, RuboCop, bundler-audit, and Brakeman, but not RSpec.
- **Risk:** developers can get a green local signal while shipping red tests.
- **Fix direction:** either add `bundle exec rspec` or rename/document the script as "lint and security only".

## P2 - Missing or weak tests

### 15) No direct coverage for the price-proximity liquidation exit

- **Files:** `backend/app/services/trading/near_liquidation_exit.rb`
- **Gap:** the price-distance emergency exit path has a spec file (`near_liquidation_exit_spec.rb`) but coverage should be verified for edge cases. `Trading::LiquidationEngine` has no spec file at all.
- **Add tests for:**
  - distance threshold behavior at and around `BUFFER_PCT`
  - no-op when liquidation price is absent
  - correct close side for long and short positions
  - cooldown cache prevents repeated exit attempts
  - `LiquidationEngine.evaluate_and_act!` delegates correctly to `Risk::Engine` and `Risk::Executor`

### 16) No focused unit coverage for `Trading::Handlers::OrderHandler`

- **Files:** `backend/app/services/trading/handlers/order_handler.rb`
- **Gap:** the fill-to-position-to-trade-to-event path is safety-critical but easy to regress.
- **Add tests for:**
  - filled order updates
  - event publishing
  - trade creation on close
  - error handling and reconciliation behavior

### 17) No regression test for session-scoped emergency shutdown

- **Files:** `backend/spec/services/trading/emergency_shutdown_spec.rb`
- **Gap:** existing coverage does not appear to prove that only the target session is flattened.
- **Add tests for:**
  - two sessions with active positions
  - only the target session's positions and orders are touched

### 18) No regression tests for cross-portfolio contamination in `RiskManager`

- **Files:** `backend/spec/services/trading/risk_manager_spec.rb` or nearest equivalent
- **Gap:** risk checks need explicit scope tests because the code mixes global and per-portfolio queries.
- **Add tests for:**
  - unrelated active positions do not affect portfolio-scoped checks
  - max positions and margin utilization follow the intended policy

### 19) Frontend has no automated tests in CI

- **Files:** `frontend/package.json`, `.github/workflows/ci.yml`
- **Gap:** CI runs lint, audit, and build only.
- **Fix direction:** add a lightweight test layer for critical UI and stateful behavior.

## P3 - Documentation and configuration drift

### 20) Historical planning docs disagree with the current stack

- **Files:**
  - `docs/superpowers/plans/2026-03-26-delta-exchange-bot.md`
  - `docs/superpowers/plans/2026-03-28-minimal-winning-stack.md`
  - `backend/docs/superpowers/plans/2026-03-26-rails-bot-integration.md`
- **Problem:** some docs still mention old Ruby versions, old frontend versions, outdated path assumptions, or outdated file targets.
- **Risk:** contributors follow stale instructions and reinforce legacy paths.
- **Fix direction:** mark historical docs clearly or refresh them to point at the current backend-first architecture.

### 21) Repo docs still admit configuration drift instead of preventing it

- **Files:** `README.md`, `config/bot.yml`, `backend/config/bot.yml`
- **Problem:** the README tells users to keep two bot config files aligned if both are used.
- **Risk:** duplicated config invites silent divergence.
- **Fix direction:** choose one source of truth, generate one from the other, or add a drift check.

### 22) `.github/README.md` softens a hard CI requirement

- **Files:** `.github/README.md`, `.github/workflows/ci.yml`
- **Problem:** `DELTA_EXCHANGE_REPOSITORY` is described as optional even though CI fails without the path gem being available.
- **Risk:** onboarding friction and incorrect expectations.
- **Fix direction:** rewrite the docs to distinguish "optional extra checkout" from "required path availability".

## Code review checklist gaps

These problems are broad enough that they deserve explicit review prompts:

1. **Scope clarity**
   - Is this query intentionally global, or should it be scoped by session or portfolio?
   - Does the method name make that scope obvious?

2. **Boundary normalization**
   - Are exchange-side strings normalized at one boundary, or are raw values leaking into domain logic?

3. **Duplicate implementation check**
   - Does a matching class or behavior also exist under root `lib/bot/` or root `spec/`?
   - If so, should one be deleted instead of updated?

4. **Error policy**
   - Is this broad rescue appropriate here?
   - If not, should the code re-raise, reconcile, or fail the session explicitly?

5. **Naming clarity**
   - Would a new reviewer confuse this class with another one that already exists?

## Suggested cleanup sequence

### First wave

- [ ] Fix session and portfolio scoping in `EmergencyShutdown` and `RiskManager`
- [ ] Add regression tests for the scoping fixes
- [ ] Add cross-reference comments and contract specs clarifying `Risk::LiquidationGuard`, `NearLiquidationExit`, and `LiquidationEngine` boundaries
- [ ] Add spec coverage for `LiquidationEngine` and verify `NearLiquidationExit` edge cases

### Second wave

- [ ] Decide the fate of root `lib/bot/` and root `spec/`
- [ ] Remove or deprecate `bin/test_indicators.rb`
- [ ] Consolidate duplicate WebSocket patch code
- [ ] Normalize side handling across repositories and services

### Third wave

- [ ] Make `ollama-client` provisioning explicit and reproducible
- [ ] Add frontend tests to CI
- [ ] Clarify `backend/bin/ci`
- [ ] Mark or refresh stale planning docs
- [ ] Reduce duplicated bot configuration sources

## Deletion candidates to evaluate

These are not confirmed safe to remove yet, but they deserve an explicit keep-or-delete decision:

- `lib/bot/runner.rb`
- root `lib/bot/**` files that duplicate backend behavior
- root `spec/bot/**`
- `lib/bot/indicators/provider.rb`
- `bin/test_indicators.rb`
- stale historical planning docs under `docs/superpowers/**` once superseded

## Definition of done for future cleanup PRs

- code names reveal intent without extra explanation
- session or portfolio scoping is explicit
- duplicate legacy paths are either removed or clearly deprecated
- tests cover the real backend runtime, not a parallel copy
- docs point contributors at one supported workflow
