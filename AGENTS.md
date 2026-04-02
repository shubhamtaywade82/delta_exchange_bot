# AGENTS.md

Operational guide for autonomous coding agents working in this repository.

## 1) Mission and scope

- Build and maintain the Delta Exchange futures bot stack.
- Prefer changing the canonical Rails runtime under `backend/`.
- Treat root `lib/bot/` as legacy unless a task explicitly targets it.

## 2) Architecture facts to respect

- Canonical runtime: `backend/` Rails app (`Trading::Runner`, API, DB, jobs).
- `./bin/run` delegates to `backend/bin/bot`.
- Do not run multiple long-lived trading loops for the same session.
- Do not run `bin/bot` and `DeltaTradingJob` concurrently for one session.

## 3) Safe operating defaults

- Default to paper/dry mode while developing.
- Never enable live trading paths unless the task explicitly requires it.
- Prefer deterministic behavior and explicit failure over hidden retries.

## 4) Setup and run commands

- Install deps: `cd backend && bundle install`
- Start full dev stack: `./bin/dev`
- Start bot process directly: `cd backend && bin/bot`
- Run primary tests: `cd backend && bundle exec rspec`

## 5) Code style expectations (Clean Ruby, strict)

- Prefer deletion over addition when possible.
- Call out unclear names and rename immediately.
- Reject long methods; split methods over ~5 lines unless clearly justified.
- Enforce single responsibility in classes and methods.
- Use guard clauses; avoid deep nesting and if/else chains.
- Avoid boolean flags that alter method behavior.
- Avoid returning hashes with mixed meanings.
- Remove unnecessary indirection and premature abstractions.
- If code needs a comment to explain intent, refactor for clarity instead.

## 6) Testing expectations

- Tests must read as clearly as production code.
- Use RSpec `context` blocks to group behavior.
- Example descriptions must describe behavior, not implementation details.
- Keep one behavior per example.
- Use explicit expected and actual values in assertions.
- Avoid complex setup that hides test intent.

## 7) Refactoring posture

- Refactor continuously while making changes.
- No improvement is too small if it improves clarity.
- Extract intention-revealing methods instead of inline complexity.
- Reduce duplication aggressively.

## 8) Change strategy

- Favor the smallest change that solves the real problem.
- Avoid speculative optimization and unnecessary new dependencies.
- Keep interfaces stable unless the task requires API changes.
- Preserve existing user changes; never revert unrelated edits.

## 9) Definition of done for agent changes

1. Code is clear, small, and intention-revealing.
2. Relevant tests pass (`bundle exec rspec` in `backend`).
3. Risky behavior changes are documented in PR notes.
4. No accidental live-trading activation was introduced.

