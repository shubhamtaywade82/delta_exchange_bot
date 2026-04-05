---
name: delta-bot-clean-ruby-pr
description: >-
  Enforces this repository's Ruby style, safety defaults, and PR hygiene for backend/ changes.
  Use when writing or reviewing Ruby/Rails in delta_exchange_bot, refactoring services, adding RSpec,
  or when the user asks for a commit message, PR description, or pre-merge checklist.
---

# Delta bot — Clean Ruby and PR expectations

## Non-negotiables (repo)

- Root **`AGENTS.md`**: Clean Ruby, explicit names, short methods, guard clauses, tests for behavior changes, smallest diff that solves the problem.
- **Paper / dry by default** — do not turn on live trading or real order paths unless the task explicitly requires it.
- **Canonical path:** `backend/` — avoid expanding root `lib/bot/`.
- **No cross-broker leakage:** Delta Exchange India only; no DhanHQ APIs in this repo.

## Ruby / Rails

- Service objects own trading logic; keep controllers thin.
- Prefer **`BigDecimal`** for money-critical paths where the codebase already does; do not widen `to_f` usage in execution/risk without justification.
- Swallowed errors on hot paths should use **`HotPathErrorPolicy.log_swallowed_error`** where the codebase already does — match existing patterns.
- RSpec: `context` grouping, examples describe **behavior**, one main expectation per example where practical.

## Verification before merge

```bash
cd backend && bundle exec rspec
```

Run RuboCop on touched files if the change is Ruby-heavy:

```bash
cd backend && bundle exec rubocop path/to/file.rb
```

## PR / commit copy

- Use **complete sentences**; state **what** and **why**; call out risky behavior (e.g. risk scope, Telegram, live mode).
- If behavior changes affect operators, mention **env vars**, **Settings keys**, or **Redis keys** they need to know.

## Quick self-review (from AGENTS.md)

- Names intention-revealing? Any method doing two jobs? Guard clauses? Single class responsibility? Deletable code instead of new layers? Tests readable?
