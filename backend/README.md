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
- `Trading::Risk::LiquidationGuard` (margin-ratio classification on ticks / after fills)
- `Trading::Risk::PortfolioGuard` (PnL / exposure limits for new entries)
- `Trading::Risk::Engine`
- `Trading::Risk::Executor`

`Trading::NearLiquidationExit` runs in the runner loop and force-exits when cached LTP is within a small band of the position’s liquidation price (distinct from margin-ratio `Risk::LiquidationGuard`).

`Trading::EmergencyShutdown` flattens **open positions for the session’s portfolio** and cancels that session’s orders (operational stop). `ExecutionEngine` checks `PortfolioGuard` before placing any new order.
`ExecutionEngine` always applies `Risk::MarginAffordability` in paper mode (unless paper override is active). In live mode, the same pre-submit check is optional via `RISK_LIVE_MARGIN_AFFORDABILITY_ENABLED` because it relies on portfolio snapshot freshness.

When **`PAPER_USE_ORDERBOOK_SIMULATOR=true`**, paper `ExecutionEngine` uses the same synthetic order book + matching + impact stack as `PaperTrading::ProcessSignalJob` (via `PaperTrading::DeltaLikeFillSimulator`), applies **taker/maker fees** to each `Fill`, and debits fees from **`Portfolio` balance** (`balance_delta = realized_pnl − fee` per fill). **`PAPER_LIMIT_FILL_STRICT`**: no fallback to instant fill when the book yields no slices. **`PAPER_EXEC_DELAY_MS`**: optional **one** delay per order batch on the runner path (default `0` in tests); `FillApplier` still applies per-fill delay on the paper-wallet path.
Paper close-and-flip behavior is conservative: the close leg is committed first; if excess flip margin is unaffordable or flip persistence fails, the flip leg is skipped (logged) instead of rolling back the close.


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

## Analysis dashboard and SMC Telegram

- **Scheduled digest:** `Trading::AnalysisDashboardRefreshJob` (Solid Queue — `config/recurring.yml`, default every **15 minutes**) builds multi-timeframe SMC + optional **`AiSmcSynthesizer`** (Ollama) output and writes **`delta:analysis:dashboard`** (`Trading::Analysis::Store`). When Telegram **`notifications.telegram.events.analysis`** is enabled, `DigestTelegramPush` sends the digest **`ai_insight`** in chunks.
- **Event alerts:** While **`Trading::Runner`** is running, **`tick_received`** invokes **`Trading::Analysis::SmcAlertTickSubscriber`** → **`SmcAlertEvaluator`**, which compares confluence flags on rising edges, throttles via Redis, and can attach the same style of Ollama summary once per burst (`DigestBuilder.ai_synthesis_from_loaded_candles`). Full behavior, env vars, and Redis keys: [`docs/smc_event_alerts.md`](docs/smc_event_alerts.md).

## Paper INR wallet flow (SOLUSD contract math)

- Paper fills are applied by `PaperTrading::FillApplier`, which writes fills then delegates to `PositionManager` for margin lock/release, fee booking, and realized PnL booking.
- Margin/fees/PnL are computed from USD contract math first (`contracts × contract_value × price`) and converted to INR via `Finance::UsdInrRate` (default 85 in tests).
- Fee rate uses GST-inclusive effective taker fee by default: `taker_fee_rate × 1.18`; override with product metadata key `gst_multiplier` when needed.
- `PaperTrading::PositionAggregator` exposes position read-model fields: side, contracts, average entry, contract value, and used margin in INR.
- Paper fills persist `filled_qty`, `closed_qty`, and `margin_inr_per_fill`; partial exits release margin FIFO from those fill rows for exchange-parity accounting.
- Fill fees are liquidity-aware: pass `maker` or `taker` on fill apply and fee math uses the matching base rate before GST multiplier.
- A maintenance-margin guard liquidates product positions when `equity_inr` falls below the configured maintenance requirement.
- Liquidation guard requires a mark price from `Rails.cache["mark_price:<symbol>"]` (no LTP fallback), then computes deterministic liquidation quantity from maintenance deficit, then liquidates contracts in bounded steps until maintenance safety is restored; each step books liquidation fee + realized PnL.
- Ledger rows are idempotent per fill via `external_ref` + `sub_type` to avoid duplicate margin/fee/pnl rows under retries/concurrency.
- Liquidation skips when mark payload is stale (`PAPER_MARK_MAX_AGE_SECONDS`) and clamps wallet equity floor at zero after forced liquidation to prevent negative equity snapshots.
- `PaperTrading::FundingApplier` applies periodic funding cashflows (`sub_type: funding`) from mark notional and long/short direction into the INR ledger. Funding supports interval prorating via `last_funding_at` and `PAPER_FUNDING_INTERVAL_SECONDS`.
- `FillApplier` now supports execution realism hooks: bid/ask spread fills, non-linear impact slippage (`(size/depth)^1.5`) with cap, optional volatility spread factor, and optional delay distribution (`PAPER_EXEC_DELAY_MS` + `PAPER_EXEC_DELAY_STD_MS`).
- `PaperTrading::MatchingEngine` now executes market/limit paper orders against an in-memory order book, supports partial fills across levels, and forwards each fill through `FillApplier` (no direct wallet mutation in matching layer).
- `PaperTrading::ImpactModel` applies non-linear execution impact (`PAPER_IMPACT_COEFF`, `PAPER_MARKET_DEPTH`) before each matched fill is applied.
- Position opens/adds enforce a paper notional cap (`PAPER_MAX_LEVERAGE_CAP`) and wallets that hit zero equity are marked `bankrupt` (trading disabled).

## Paper trading: session capital vs portfolio balance

- **`trading_sessions.capital` is USD.** Risk sizing (`Trading::OrderBuilder`, position sizer) treats it as a US dollar notional budget and converts to INR for risk math via `Finance::UsdInrRate`. Do not store INR in this column expecting USD behavior.
- **Portfolio cash is the execution ledger.** `portfolios.balance` is updated by fills and realized PnL; `available_balance` is `balance - used_margin` (initial margin on open positions). Dashboard “total equity” for paper is cash plus unrealized on open rows — not the same as “free cash.”
- **Reconciling the wallet card:** `total_equity = cash_balance + unrealized_pnl`. `free_cash = cash_balance - blocked_margin`. So `total_equity - blocked_margin` equals `free_cash + unrealized_pnl`, not `free_cash`. Small INR gaps vs mental math are normal because each line is rounded from USD separately.
- **Operational check:** When starting a session, confirm the linked portfolio’s opening `balance` matches the intended starting cash in the same units as your seed or migration (e.g. blank `capital` backfill historically used **10_000 USD**). If the UI shows a small INR equity number, verify you did not confuse INR display with a USD session budget.
