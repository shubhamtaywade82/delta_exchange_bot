# Delta Trading Backend

Rails API backend for the Delta trading bot runtime.

## Fill-first execution pipeline

Source-of-truth chain is now:

`Exchange fills -> fills table -> orders -> positions`

- `Fill` is persisted with unique `exchange_fill_id` and linked to `Order`.
- `Trading::FillProcessor` is idempotent via `exchange_fill_id` and recalculates order + position state under transaction/lock.
- `Trading::OrderUpdater` applies exchange order lifecycle updates and fill snapshots.

Critical transactions run under `REPEATABLE READ` to prevent stale aggregate reads during concurrent ingestion.

## WebSocket ingestion

`Trading::MarketData::WsClient` now listens to ticker + order + fill channels and routes payloads to:

- `Trading::FillProcessor` for `v2/fills`
- `Trading::OrderUpdater` for `v2/orders`

WS ingestion uses a bounded queue (`WS_INGESTION_QUEUE_SIZE`) and worker pool (`WS_INGESTION_WORKERS`) to absorb burst traffic and apply backpressure.

Overflow policy is explicit: **drop + log warning** (non-blocking enqueue), so feed threads are not stalled.

Workers are self-healed by a supervisor loop, and throughput metrics are logged (`processed`, `dropped`, `queue`) every `WS_METRICS_LOG_INTERVAL_SECONDS`.

Reconnect uses jitter via `WS_RECONNECT_BASE_SECONDS`.

## Position lifecycle state machine

`Position` transitions remain deterministic:

`init -> entry_pending -> partially_filled -> filled -> exit_pending -> closed`

Terminal states: `liquidated`, `rejected`, `closed`.

## Environment variables

Copy `.env.example` and set your broker credentials before running the bot.

## Reconciliation

`Trading::ReconciliationJob` runs every minute (Solid Queue recurring) and calls `Trading::PositionRecalculator` for every dirty position to correct drift from missed WS events.

Reconciliation uses a dirty-position strategy (`needs_reconciliation`) so only affected positions are recomputed by the periodic job.


## Risk engine

Risk runs at two hooks:
- on every tick (`WsClient#handle_tick`)
- immediately after fill processing (`FillProcessor`)

Modules:
- `Trading::Risk::PositionRisk`
- `Trading::Risk::MarginCalculator`
- `Trading::Risk::LiquidationGuard`
- `Trading::Risk::PortfolioGuard` (PnL / exposure limits for new entries)
- `Trading::Risk::Engine`
- `Trading::Risk::Executor`

`Trading::EmergencyShutdown` flattens positions and cancels session orders (operational stop). `ExecutionEngine` checks `PortfolioGuard` before placing any new order.


## Microstructure execution layer

Orderbook updates (`v2/orderbook`) are processed by:
- `Trading::Orderbook::Book` (L2 state)
- `Trading::Microstructure::Imbalance` + `SignalEngine`
- `Trading::Execution::DecisionEngine` (maker/taker choice)
- `Trading::Execution::OrderRouter` (post_only/reduce_only aware placement)

Execution is throttled through `Trading::Execution::RateLimiter` and supports batch submission via `Trading::Execution::BatchExecutor`.


## Adaptive strategy layer

Adaptive flow:
`Features::Extractor -> Strategy::RegimeDetector -> Strategy::AiEdgeModel (cached) -> Strategy::Selector -> Strategies::* -> Execution::OrderRouter`

AI is used only for meta-configuration (strategy/risk multipliers), never direct trade placement.
Deterministic fallback is always available via `AiEdgeModel.fallback`.

`Trading::AdaptiveEngine` is invoked from orderbook updates and keeps AI calls cached (`AI_CONFIG_CACHE_SECONDS`).


## Online learning loop

Loop:
`Execution -> Learning::CreditAssigner -> Learning::Reward -> Learning::OnlineUpdater -> Learning::Metrics -> next strategy choice`

- Updates are bounded (`OnlineUpdater::CLIP`) and clamped to safe ranges.
- Learning pauses automatically when portfolio PnL breaches `LEARNING_FREEZE_PNL`.
- `AiRefinementJob` runs off-path (every 10 minutes) to suggest parameter bounds; execution remains deterministic.

## Paper trading: session capital vs portfolio balance

- **`trading_sessions.capital` is USD.** Risk sizing (`Trading::OrderBuilder`, position sizer) treats it as a US dollar notional budget and converts to INR for risk math via `Finance::UsdInrRate`. Do not store INR in this column expecting USD behavior.
- **Portfolio cash is the execution ledger.** `portfolios.balance` is updated by fills and realized PnL; `available_balance` is `balance - used_margin` (initial margin on open positions). Dashboard “total equity” for paper is cash plus unrealized on open rows — not the same as “free cash.”
- **Reconciling the wallet card:** `total_equity = cash_balance + unrealized_pnl`. `free_cash = cash_balance - blocked_margin`. So `total_equity - blocked_margin` equals `free_cash + unrealized_pnl`, not `free_cash`. Small INR gaps vs mental math are normal because each line is rounded from USD separately.
- **Operational check:** When starting a session, confirm the linked portfolio’s opening `balance` matches the intended starting cash in the same units as your seed or migration (e.g. blank `capital` backfill historically used **10_000 USD**). If the UI shows a small INR equity number, verify you did not confuse INR display with a USD session budget.
