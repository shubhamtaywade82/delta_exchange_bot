# Changelog

## 2026-03-30
- Added online reinforcement loop modules: `Learning::Reward`, `CreditAssigner`, `OnlineUpdater`, `ParamProvider`, `Explorer`, and `Metrics`.
- Added `StrategyParam` model + migration scaffolding for bounded per-strategy/regime parameter updates.
- Added adaptive trade outcome schema migration for `trades` (`realized_pnl`, `fees`, `holding_time_ms`, `features`) and strategy/regime indexing.
- Integrated learning hooks on position close (`OrdersRepository.close_position`) to finalize trade credit and update online params/metrics.
- Added low-priority `Trading::Learning::AiRefinementJob` for periodic off-path parameter bound refinement.
- Integrated adaptive strategy context persistence in WS orderbook path (`adaptive:entry_context:*`).
