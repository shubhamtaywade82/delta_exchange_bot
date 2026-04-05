# Changelog

## 2026-04-05
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
