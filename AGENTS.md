# AGENTS.md

Operational guide and non-negotiable standards for AI and human agents in this repository.

Primary goal: ship readable, maintainable Ruby code that is safe to change.

## Mission and scope

- Build and maintain the Delta Exchange futures bot stack.
- Prefer changing the canonical Rails runtime under `backend/`.
- Treat root `lib/bot/` as legacy unless a task explicitly targets it.

## Architecture facts to respect

- Configuration vs DB vs cache precedence (bot config merge, Redis, Postgres): see [backend/docs/configuration_precedence.md](backend/docs/configuration_precedence.md).
- Canonical runtime: `backend/` Rails app (`Trading::Runner`, API, DB, jobs).
- `./bin/run` delegates to `backend/bin/bot`.
- Do not run multiple long-lived trading loops for the same session.
- Do not run `bin/bot` and `DeltaTradingJob` concurrently for one session.

## Safe operating defaults

- Default to paper/dry mode while developing.
- Never enable live trading paths unless the task explicitly requires it.
- Prefer deterministic behavior and explicit failure over hidden retries.

## Setup and run commands

- Install deps: `cd backend && bundle install`
- Start full dev stack: `./bin/dev`
- Start bot process directly: `cd backend && bin/bot`
- Run primary tests: `cd backend && bundle exec rspec`

## Core working mindset

1. Favor clarity over speed.
2. Avoid premature optimization.
3. Do not chase perfect code at the cost of shipping.
4. Write code that invites change instead of resisting it.
5. Leave code better than you found it.
6. Assume the next developer is you in 6 months.

## Clean Ruby (enforced)

1. Call out unclear names immediately and rename them.
2. Reject long methods unless there is explicit justification.
3. Highlight hidden responsibilities and split them.
4. Flag unnecessary complexity; simplify aggressively.
5. Demand refactoring instead of adding explanations.
6. Prefer deletion over addition when possible.

Code must be straightforward and self-explanatory. If intent is unclear, refactor.

## Naming rules

1. Names must reveal intent without extra context.
2. Method names must be verbs.
3. Variables must describe the data they hold.
4. Avoid abbreviations, single-letter names, and ambiguous terms.
5. Choose good names immediately; do not defer naming quality.
6. Do not encode types in names.
7. Class names must communicate role and intent.
8. Module names must represent grouped behavior, not object identity.

## Method rules

1. A method does one thing.
2. Methods longer than about 5 lines should be reviewed and usually split.
3. Use guard clauses for input and state validation.
4. Avoid deep nesting.
5. Return one predictable type.
6. Do not use boolean flags to switch behavior.
7. Do not return hashes with mixed meanings.

## Conditional logic rules

1. Prefer guard clauses over if/else chains.
2. Avoid double negatives.
3. Avoid deeply nested conditionals.
4. Prefer Ruby built-ins over manual branching.
5. Replace conditionals with polymorphism when appropriate.

## Class design rules

1. Each class must have one clear responsibility.
2. Avoid generic class names that invite misuse.
3. Prefer composition over inheritance.
4. Keep inheritance shallow.
5. Move unrelated behavior into separate classes/modules.
6. Hide internal behavior with private methods.
7. Class names must clearly communicate purpose.

## Refactoring rules

1. No improvement is too small.
2. Refactor continuously while changing code.
3. Remove comments once code is self-explanatory.
4. Extract named methods instead of writing explanatory inline comments.
5. Encapsulate behavior behind intention-revealing names.
6. Eliminate duplication aggressively.

## Testing rules (RSpec)

1. Tests must be as readable as production code.
2. Use `context` blocks to group behavior.
3. Example descriptions must describe behavior, not implementation details.
4. Explicitly name expected and actual values.
5. Avoid complex setup that hides intent.
6. Each example should verify one behavior.

## Change strategy

- Favor the smallest change that solves the real problem.
- Avoid speculative optimization and unnecessary new dependencies.
- Keep interfaces stable unless the task requires API changes.
- Preserve existing user changes; never revert unrelated edits.

## Definition of done for agent changes

1. Code is clear, small, and intention-revealing.
2. Relevant tests pass (`bundle exec rspec` in `backend`).
3. Risky behavior changes are documented in PR notes.
4. No accidental live-trading activation was introduced.

## Agent review checklist (before commit)

- Are names explicit and intention-revealing?
- Can any method be split for clarity?
- Are guard clauses used to flatten logic?
- Is any class doing more than one job?
- Can code be deleted instead of added?
- Are tests behavior-focused and easy to read?
- Did this change make the codebase simpler?

If any answer is "no", refactor before finalizing.
