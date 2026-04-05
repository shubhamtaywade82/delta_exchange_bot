# Changelog

## 2026-04-05

- Added INR-ledger paper fill flow helpers: `PaperTrading::FillApplier`, `PaperTrading::WalletLedgerEntry`, and `PaperTrading::PositionAggregator`; retained `FillApplicator` as compatibility wrapper.
- Paper fees now apply GST-inclusive effective rate by default (`0.05% × 1.18 = 0.059%`) via `PaperTrading::Fees.effective_fee_rate_for_product` with optional per-product `gst_multiplier` metadata override.
- Added `Delta::ProductSync` wrapper for paper `/v2/products` sync and switched signal execution to `FillApplier`.
- Added specs covering GST fee rate math, SOLUSD long lifecycle INR-ledger outcomes, and position aggregation fields.
- Paper fill accounting now persists `filled_qty`, `closed_qty`, `margin_inr_per_fill`, and `liquidity` so partial exits release FIFO margin from entry fills instead of proportional snapshot math.
- Fee model now supports maker/taker selection per fill liquidity (`maker`/`taker`) with GST multiplier applied on top.
- Added maintenance margin guard in `PositionManager` that liquidates open paper positions for the product when wallet equity drops below requirement.
- Liquidation checks now use mark price precedence (Redis cache `mark_price:<symbol>` → product mark price → trigger price), and forced liquidations book liquidation fee + realized PnL in ledger rows.
- Added ledger idempotency key (`external_ref`) with unique index across wallet/ref/entry_type to prevent duplicate financial rows on fill reprocessing.
- Liquidation path now uses strict mark-price cache input (skips liquidation cycle when mark is missing) and performs incremental step liquidation until maintenance safety is restored.
- Ledger idempotency key expanded with `sub_type` so one fill can safely emit multiple unique ledger rows (entry fee, exit fee, margin lock/release, pnl, liquidation fee).
- Added advisory transaction lock (`pg_advisory_xact_lock`) by fill id around fill application to harden distributed worker contention.
- Liquidation sizing now computes required close quantity from maintenance deficit before applying liquidation steps, reducing over-liquidation/oscillation risk.
- Liquidation now validates mark freshness (`PAPER_MARK_MAX_AGE_SECONDS`) and clamps wallet equity/balance floor to zero after forced liquidation to prevent negative-equity drift.
- Liquidation ledger subtypes normalized to bounded names (`liquidation_margin_release`, `liquidation_fee`, `liquidation_pnl`) with step-specific `external_ref` tokens.
- Added `PaperTrading::FundingApplier` + `ApplyFundingJob` to book periodic funding cashflows into ledger rows (`entry_type: funding`).
- Added execution realism in `FillApplier`: spread-aware bid/ask fills, configurable slippage/impact by depth, and optional execution delay.
- Added paper notional cap guard (`PAPER_MAX_LEVERAGE_CAP`) and terminal wallet state (`status=bankrupt`) when forced liquidation clamps equity to zero.
- Funding engine now supports prorated accrual by elapsed time (`last_funding_at` on positions + `PAPER_FUNDING_INTERVAL_SECONDS`).
- Execution realism upgraded to non-linear slippage impact with optional cap (`PAPER_MAX_SLIPPAGE_BPS`) and delay variance (`PAPER_EXEC_DELAY_STD_MS`).
- Added volatility spread factor knob (`PAPER_VOLATILITY_FACTOR`) for stress simulations.
- Added `PaperTrading::OrderBook`, `PaperTrading::MatchingEngine`, and `PaperTrading::ImpactModel` for orderbook-driven paper execution with partial fills and taker/maker crossing behavior.
- `PaperTrading::ProcessSignalJob` now routes fills through matching + impact layers before invoking `FillApplier` per fill, rejecting signals when no orderbook liquidity is available.
- Added paper execution knobs: `PAPER_IMPACT_COEFF` and `PAPER_MARKET_DEPTH`.
- **SMC event Telegram alerts:** `Trading::Analysis::SmcAlertEvaluator` + `SmcAlertTickSubscriber`, wired from `Trading::Runner` on `tick_received`. Rising-edge detection vs Redis `delta:smc_alert:prev:*`, throttle gate and per-alert cooldowns, optional Ollama summary once per burst via `DigestBuilder.ai_synthesis_from_loaded_candles` / `AiSmcSynthesizer`. Telegram: `notify_smc_confluence_event` + chunked `AI (SMC EVENT)` follow-up. Env: `ANALYSIS_SMC_ALERT_*` (see `backend/docs/smc_event_alerts.md`).
- **Confluence schema:** `pdh_sweep` / `pdl_sweep` exposed on `SmcConfluence::BarResult` and in `SmcConfluenceMtf` alignment; digest rounding updated.
- **Fresh start:** `delta:smc_alert:*` included in Redis `SCAN` cleanup.
- Tightened paper broker margin flow: margin reservations now validate available INR before open/add/flip using `contract_value` + leverage math at fill time.
- `PaperTrading::ProcessSignalJob` now rejects unaffordable signals using fill-price affordability and only enqueues `RepriceWalletJob` after successful fills.
- Extended `Trading::ExecutionEngine` affordability checks to live mode too, so oversized entries are rejected before order persistence when portfolio cash snapshot cannot fund incremental margin.
- Scoped paper risk override bypass logic to paper mode only, and lock `PaperTradingSignal` rows with `with_lock` during processing to avoid duplicate order/fill races.
- Centralized paper margin estimation in `PaperTrading::PositionManager.estimate_margin_inr`, restored wallet row locking in `ProcessSignalJob`, and made live affordability guard explicitly opt-in via `RISK_LIVE_MARGIN_AFFORDABILITY_ENABLED`.
- `ProcessSignalJob` now persists rejection status outside rollback path when fill application raises `InsufficientMarginError`, preventing pending-signal reprocessing loops.
- `PositionManager` now owns an outer transaction in `apply_fill`, wraps close/flip mutations atomically, and adds a defensive fallback when product-scoped reserved-margin ledger rows are missing.
- `PositionManager` now preserves close execution when a flip excess leg is unaffordable (logs and skips flip instead of rolling back the close).
- `PositionManager#ensure_sufficient_margin!` now uses in-transaction wallet snapshot values directly (no forced reload).
- Flip-open now runs in a `requires_new` transaction and skips safely on `InsufficientMarginError` or `RecordInvalid`, keeping completed close legs intact.

## 2026-03-30
- Added online reinforcement loop modules: `Learning::Reward`, `CreditAssigner`, `OnlineUpdater`, `ParamProvider`, `Explorer`, and `Metrics`.
- Added `StrategyParam` model + migration scaffolding for bounded per-strategy/regime parameter updates.
- Added adaptive trade outcome schema migration for `trades` (`realized_pnl`, `fees`, `holding_time_ms`, `features`) and strategy/regime indexing.
- Integrated learning hooks on position close (`OrdersRepository.close_position`) to finalize trade credit and update online params/metrics.
- Added low-priority `Trading::Learning::AiRefinementJob` for periodic off-path parameter bound refinement.
- Integrated adaptive strategy context persistence in WS orderbook path (`adaptive:entry_context:*`).
